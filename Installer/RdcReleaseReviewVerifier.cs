// RDC Relay 1.6.0, OFFLINE review-only package verifier.
// Never launches Host, GUI, installer or Remote. Never writes registry/files.
// A verified candidate is NOT publisher-authenticated or installable.
using System;
using System.IO;
using System.Reflection;

[assembly:AssemblyTitle("RDC Relay Offline Review Verifier")]
[assembly:AssemblyProduct("RDC Relay")]
[assembly:AssemblyCompany("RUBASS")]
[assembly:AssemblyVersion("1.6.0.0")]
[assembly:AssemblyFileVersion("1.6.0.0")]

internal static class RdcReleaseReviewVerifier {
 static int Main(string[] args) {
  if(args==null||args.Length!=2||
     !String.Equals(args[0],"--verify",StringComparison.Ordinal)){
   Console.Error.WriteLine("RDC_REVIEW_VERIFIER_USAGE: --verify <extracted-package-folder>");
   Console.Error.WriteLine("RDC_RELEASE_REVIEW_NO_INSTALL_OR_REMOTE");
   return 42;
  }
  try {
   var list=RdcReleaseReviewPackage.Validate(args[1]);
   if(list.Count!=RdcReleaseReviewPackage.Required.Length)
    throw new IOException("RDC_REVIEW_VERIFIER_MEMBER_COUNT");
   Console.WriteLine("RDC_RELEASE_REVIEW_PACKAGE_PASS="+list.Count+" FAIL=0");
   Console.WriteLine("RDC_RELEASE_REVIEW_INSTALLABLE=FALSE");
   Console.WriteLine("RDC_RELEASE_REVIEW_AUTHENTICATED_PUBLISHER=NOT_CHECKED");
   return 0;
  }catch(Exception problem) {
   // Source paths or file contents can contain user data: only emit safe
   // bounded error codes, not raw exception text or the provided folder.
   string code=problem.Message??"";
   if(!System.Text.RegularExpressions.Regex.IsMatch(code,
      @"\ARDC_REVIEW_[A-Z0-9_]{3,100}\z"))code=problem.GetType().Name;
   Console.Error.WriteLine("RDC_RELEASE_REVIEW_PACKAGE_REFUSED:"+code);
   return 42;
  }
 }
}
