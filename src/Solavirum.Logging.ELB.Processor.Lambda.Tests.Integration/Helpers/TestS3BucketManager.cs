using System;
using Amazon.S3;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Helpers
{
	public class TestS3BucketManager
	{
		public TestS3BucketManager(IAmazonS3 s3, string bucketPrefix)
		{
			_s3 = s3;
			_bucketPrefix = bucketPrefix;
		}

		private readonly IAmazonS3 _s3;
		private readonly string _bucketPrefix;

		public TestS3Bucket Make()
		{
			return new TestS3Bucket(_s3, _bucketPrefix + Guid.NewGuid().ToString().Substring(0, 8));
		}
	}
}