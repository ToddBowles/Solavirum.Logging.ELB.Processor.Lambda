using System;
using System.Linq;
using System.Net;
using Amazon.S3;
using Amazon.S3.Model;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Helpers
{
	public class TestS3Bucket : IDisposable
	{
		public TestS3Bucket(IAmazonS3 s3, string bucketName = null)
		{
			_s3 = s3;
			Name = bucketName;

			var response = _s3.PutBucketAsync(Name).Result;
			if (response.HttpStatusCode == HttpStatusCode.OK) return;

			const string template = "Failed to create S3 bucket named '{0}' for use in tests. " +
			                        "Check that you have a profile set in the AWS Explorer " +
			                        "and that the selected profile has permissions to create S3 buckets";

			throw new Exception(string.Format((string) template, (object) Name));
		}

		private readonly IAmazonS3 _s3;
		public readonly string Name;

		public int GetFileCount()
		{
			return _s3.ListObjectsAsync(Name).Result.S3Objects.Count;
		}

		public void Dispose()
		{
			var objects = _s3.ListObjectsAsync(Name).Result;
			var keys = Enumerable.Select<S3Object, KeyVersion>(objects.S3Objects, o => new KeyVersion() { Key = o.Key }).ToList();
			if (keys.Any())
			{
				var deleteResult = _s3.DeleteObjectsAsync(new DeleteObjectsRequest()
				{
					BucketName = Name,
					Objects = keys
				}).Result;
			}

			var deleteResponse = _s3.DeleteBucketAsync(Name).Result;

			// apparently no content means successfull :|
			if (deleteResponse.HttpStatusCode == HttpStatusCode.NoContent) return;

			const string template = "Failed to delete S3 bucket with name '{0}' after tests ran. " +
			                        "You will need to clean this bucket up manually.";
			throw new Exception(string.Format((string) template, (object) Name));
		}
	}
}