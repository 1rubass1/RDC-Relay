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
