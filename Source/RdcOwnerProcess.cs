// RDC Relay 1.6 owner-process safety contract.
// Production-source code; no process launch, termination, credential or network APIs.
// Fail closed for unknown and adopted Remote until independent OS-tree review.
using System;
using System.Collections.Generic;
using System.IO;

namespace RdcRelay.Owner
{
    public enum Ownership { Unknown, Adopted, Owned }
    public enum StopDecision { RefuseUnknown, RefuseAdopted, RefuseUnverified, RefuseNoApproval, EligibleForCooperativeStop }

    public sealed class ProcessEvidence
    {
        public int Pid { get; private set; }
        public long BirthUtcTicks { get; private set; }
        public int SessionId { get; private set; }
        public int ParentPid { get; private set; }
        public string ExecutablePath { get; private set; }
        public string InstallRoot { get; private set; }
        public string OwnerRunId { get; private set; }
        public Ownership Kind { get; private set; }

        public ProcessEvidence(int pid, long birthUtcTicks, int sessionId, int parentPid,
            string executablePath, string installRoot, string ownerRunId, Ownership kind)
        {
            Pid = pid;
            BirthUtcTicks = birthUtcTicks;
            SessionId = sessionId;
            ParentPid = parentPid;
            ExecutablePath = executablePath ?? "";
            InstallRoot = installRoot ?? "";
            OwnerRunId = ownerRunId ?? "";
            Kind = kind;
        }
    }

    public static class ProcessOwnership
    {
        static bool SamePath(string left, string right)
        {
            try {
                return String.Equals(Path.GetFullPath(left), Path.GetFullPath(right),
                    StringComparison.OrdinalIgnoreCase);
            } catch { return false; }
        }

        static bool SafeRunId(string id)
        {
            Guid parsed;
            return id != null && id.Length == 32 && Guid.TryParseExact(id, "N", out parsed)
                && String.Equals(parsed.ToString("N"), id, StringComparison.Ordinal);
        }

        // expected is recorded at actual process birth; observed MUST be populated
        // by the OS, never from a GUI/IPC client-supplied PID or JSON.
        public static bool SameVerifiedProcess(ProcessEvidence expected, ProcessEvidence observed)
        {
            if (expected == null || observed == null) return false;
            if (expected.Kind != Ownership.Owned || observed.Kind != Ownership.Owned) return false;
            if (expected.Pid <= 0 || expected.BirthUtcTicks <= 0 || expected.ParentPid <= 0) return false;
            if (!SafeRunId(expected.OwnerRunId)) return false;
            if (expected.Pid != observed.Pid || expected.BirthUtcTicks != observed.BirthUtcTicks
                || expected.SessionId != observed.SessionId || expected.ParentPid != observed.ParentPid
                || !String.Equals(expected.OwnerRunId, observed.OwnerRunId, StringComparison.Ordinal))
                return false;
            if (!SamePath(expected.ExecutablePath, observed.ExecutablePath)
                || !SamePath(expected.InstallRoot, observed.InstallRoot))
                return false;
            // Executable must remain inside the verified owner installation.
            string root = Path.GetFullPath(expected.InstallRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string exe = Path.GetFullPath(expected.ExecutablePath);
            return exe.StartsWith(root + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase);
        }

        // A positive answer is NOT process termination authorization by itself.
        // The owner must still separately verify children, stop transport
        // cooperatively and confirm OS exit; forced tree kills are never used.
        public static StopDecision Evaluate(Ownership kind, ProcessEvidence expected,
            ProcessEvidence observed, bool ownerApprovedOsTrial, bool userConfirmed)
        {
            if (kind == Ownership.Unknown) return StopDecision.RefuseUnknown;
            if (kind == Ownership.Adopted) return StopDecision.RefuseAdopted;
            if (!SameVerifiedProcess(expected, observed)) return StopDecision.RefuseUnverified;
            if (!ownerApprovedOsTrial || !userConfirmed) return StopDecision.RefuseNoApproval;
            return StopDecision.EligibleForCooperativeStop;
        }

        // Installation pilot not approved yet: this function must not be called
        // as a substitute for a real OS child-tree identity and stop audit.
        public static void StopNotImplemented()
        {
            throw new InvalidOperationException("RC1_STOP_BLOCKED: owner-run process-tree test and Architect GO required");
        }
    }

    // G7: injected-only disposable tree shutdown contract. Never instantiate a
    // real Remote adapter until separately reviewed/approved OS-tree tests.
    // Production RdcOwnerRemoteState.RequireSafeStop remains an unconditional block.
    public interface IRemoteTreeObservation
    {
        // OS-derived fresh identity; null means PID is absent.
        ProcessEvidence Read(int pid);
        // All currently observed direct OS children, not names or HWND guesses.
        int[] Children(int parentPid);
    }

    public interface IRemoteCooperativeStop
    {
        // No kill API or shell command; implemented only by disposable fake.
        bool Request(ProcessEvidence pinned);
        bool AwaitExit(ProcessEvidence pinned, int timeoutMilliseconds);
    }

    public enum RemoteTreeExitCode
    {
        Complete, RefuseMode, RefuseOwnership, RefuseIdentity,
        RefuseAncestry, RefuseUnexpectedChild, RefuseTransport,
        Timeout, RefuseSurvivor
    }

    public sealed class RemoteTreeExitResult
    {
        public RemoteTreeExitCode Code { get; private set; }
        public int Requested { get; private set; }
        public int[] Pending { get; private set; }
        public bool IsClean { get { return Code == RemoteTreeExitCode.Complete && Pending.Length == 0; } }
        public RemoteTreeExitResult(RemoteTreeExitCode code, int requests, int[] pending)
        {
            Code = code;
            Requested = requests;
            Pending = pending ?? new int[0];
        }
    }

    public static class RemoteTreeCooperativeExit
    {
        static RemoteTreeExitResult Fail(RemoteTreeExitCode code, int requested,
            IList<ProcessEvidence> pinned)
        {
            List<int> pids = new List<int>();
            foreach (ProcessEvidence item in pinned) pids.Add(item.Pid);
            return new RemoteTreeExitResult(code, requested, pids.ToArray());
        }

        // Executes only against caller-injected observation/stop fakes. No OS
        // process API here. If actual Remote becomes involved, the production
        // Host's separate hard block still applies.
        public static RemoteTreeExitResult ExecuteInjected(
            ProcessEvidence recordedHost, ProcessEvidence[] recordedRemoteTree,
            IRemoteTreeObservation observation, IRemoteCooperativeStop cooperative,
            bool fakeOnly, bool specificallyApproved, bool includeHostExit,
            int totalTimeoutMilliseconds)
        {
            List<ProcessEvidence> all = new List<ProcessEvidence>();
            if (recordedRemoteTree != null) all.AddRange(recordedRemoteTree);
            if (!fakeOnly || !specificallyApproved || totalTimeoutMilliseconds < 100 ||
                totalTimeoutMilliseconds > 60000 || observation == null || cooperative == null)
                return Fail(RemoteTreeExitCode.RefuseMode, 0, all);
            if (recordedHost == null || recordedHost.Kind != Ownership.Owned ||
                recordedRemoteTree == null || recordedRemoteTree.Length == 0 ||
                recordedRemoteTree.Length > 16)
                return Fail(RemoteTreeExitCode.RefuseOwnership, 0, all);

            Dictionary<int, ProcessEvidence> byPid = new Dictionary<int, ProcessEvidence>();
            foreach (ProcessEvidence e in all)
            {
                if (e == null || e.Kind != Ownership.Owned || e.Pid <= 0 ||
                    byPid.ContainsKey(e.Pid) || e.Pid == recordedHost.Pid ||
                    !String.Equals(e.OwnerRunId, recordedHost.OwnerRunId, StringComparison.Ordinal))
                    return Fail(RemoteTreeExitCode.RefuseOwnership, 0, all);
                byPid.Add(e.Pid, e);
            }
            if (recordedRemoteTree[0].ParentPid != recordedHost.Pid)
                return Fail(RemoteTreeExitCode.RefuseAncestry, 0, all);

            // Validate every identity and all child links BEFORE sending any
            // cooperative request, including unknown/unrecorded descendants.
            ProcessEvidence freshHost = observation.Read(recordedHost.Pid);
            if (!ProcessOwnership.SameVerifiedProcess(recordedHost, freshHost))
                return Fail(RemoteTreeExitCode.RefuseIdentity, 0, all);
            HashSet<int> direct = new HashSet<int>(observation.Children(recordedHost.Pid) ?? new int[0]);
            if (!direct.Contains(recordedRemoteTree[0].Pid))
                return Fail(RemoteTreeExitCode.RefuseAncestry, 0, all);
            Dictionary<int, int> depths = new Dictionary<int, int>();
            depths[recordedRemoteTree[0].Pid] = 1;
            for (int round = 0; round < byPid.Count; round++)
            {
                bool progressed = false;
                foreach (ProcessEvidence child in all)
                {
                    if (depths.ContainsKey(child.Pid)) continue;
                    int parentDepth;
                    if (byPid.ContainsKey(child.ParentPid) &&
                        depths.TryGetValue(child.ParentPid, out parentDepth))
                    {
                        depths[child.Pid] = parentDepth + 1;
                        progressed = true;
                    }
                }
                if (!progressed) break;
            }
            if (depths.Count != byPid.Count)
                return Fail(RemoteTreeExitCode.RefuseAncestry, 0, all);
            foreach (ProcessEvidence e in all)
            {
                if (e.SessionId != recordedHost.SessionId ||
                    !ProcessOwnership.SameVerifiedProcess(e, observation.Read(e.Pid)))
                    return Fail(RemoteTreeExitCode.RefuseIdentity, 0, all);
                HashSet<int> actualChildren = new HashSet<int>(
                    observation.Children(e.Pid) ?? new int[0]);
                HashSet<int> recordedChildren = new HashSet<int>();
                foreach (ProcessEvidence maybe in all)
                    if (maybe.ParentPid == e.Pid) recordedChildren.Add(maybe.Pid);
                if (!actualChildren.SetEquals(recordedChildren))
                    return Fail(RemoteTreeExitCode.RefuseUnexpectedChild, 0, all);
            }

            // Depth-first postorder: children before parent, Host last only if
            // caller has separately requested the injected full-exit contract.
            all.Sort(delegate(ProcessEvidence a, ProcessEvidence b) {
                return depths[b.Pid].CompareTo(depths[a.Pid]);
            });
            List<ProcessEvidence> shutdown = new List<ProcessEvidence>(all);
            if (includeHostExit) shutdown.Add(recordedHost);
            System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
            int requested = 0;
            foreach (ProcessEvidence e in shutdown)
            {
                int remaining = totalTimeoutMilliseconds - (int)clock.ElapsedMilliseconds;
                if (remaining <= 0) return Fail(RemoteTreeExitCode.Timeout, requested, shutdown);
                if (!ProcessOwnership.SameVerifiedProcess(e, observation.Read(e.Pid)))
                    return Fail(RemoteTreeExitCode.RefuseIdentity, requested, shutdown);
                if (!cooperative.Request(e))
                    return Fail(RemoteTreeExitCode.RefuseTransport, requested, shutdown);
                requested++;
                if (!cooperative.AwaitExit(e, Math.Min(remaining, 5000)))
                    return Fail(RemoteTreeExitCode.Timeout, requested, shutdown);
                // Successful acknowledgement is insufficient: require fresh
                // evidence that the exact PID is absent; PID reuse is NOT clean.
                if (observation.Read(e.Pid) != null)
                    return Fail(RemoteTreeExitCode.RefuseSurvivor, requested, shutdown);
            }
            foreach (ProcessEvidence e in shutdown)
                if (observation.Read(e.Pid) != null)
                    return Fail(RemoteTreeExitCode.RefuseSurvivor, requested, shutdown);
            return new RemoteTreeExitResult(RemoteTreeExitCode.Complete, requested, new int[0]);
        }
    }

    public sealed class BoundedEventJournal
    {
        readonly object gate = new object();
        readonly Queue<string> buffer = new Queue<string>();
        readonly int capacity;
        long revision;

        public BoundedEventJournal(int capacity)
        {
            if (capacity < 1 || capacity > 1024) throw new ArgumentOutOfRangeException("capacity");
            this.capacity = capacity;
        }

        public long Revision { get { lock (gate) return revision; } }

        public long Append(string text)
        {
            if (text == null) text = "";
            if (text.Length > 2048) text = text.Substring(0, 2048);
            lock (gate) {
                revision++;
                if (buffer.Count == capacity) buffer.Dequeue();
                buffer.Enqueue(text);
                return revision;
            }
        }

        public string[] Snapshot(out long atRevision)
        {
            lock (gate) {
                atRevision = revision;
                return buffer.ToArray();
            }
        }
    }
}
