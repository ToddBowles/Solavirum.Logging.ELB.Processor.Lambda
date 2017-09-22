using System;
using Amazon;
using Amazon.Runtime;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Helpers
{
	public class AWSProfileContext : IDisposable
	{
		private AWSProfileContext(string name)
		{
		    _generator = () =>
		    {
		        try
		        {
#pragma warning disable 618
                    // I know this is obsolete, but there does not seem to be any other way to do it in .NET core right now
		            return new StoredProfileAWSCredentials(name);
#pragma warning restore 618
		        }
		        catch (Exception ex)
		        {
		            var message = $"Unexpected error while loading AWS Profile with name [{name}]\r\n" +
		                          $"The most comment reason for a failure like this is because the profile has not been configured\r\n" +
		                          "Try configuring the missing profile on this machine with one of the profile management tools\r\n" +
		                          $"For example, in Powershell try : Set-AWSCredentials -AccessKey 'secret-stuff' -SecretKey 'other-secret-stuff' -StoreAs {name}\r\n" +
                                  "If this happened on a build server, look into the build script and make sure it is configuring the profile correctly (it should be)";

		            throw new UnexpectedErrorDuringAwsProfileLoadException(message, ex);
		        }
		    };

            FallbackCredentialsFactory.CredentialsGenerators.Insert(0, _generator);
        }

		private readonly FallbackCredentialsFactory.CredentialsGenerator _generator;

		public static AWSProfileContext New(string name)
		{
			return new AWSProfileContext(name);
		}

		public void Dispose()
		{
		    FallbackCredentialsFactory.CredentialsGenerators.Remove(_generator);
		}
	}

    public class UnexpectedErrorDuringAwsProfileLoadException : Exception
    {
        public UnexpectedErrorDuringAwsProfileLoadException(string message, Exception inner)
            : base(message, inner)
        {
            
        }
    }
}