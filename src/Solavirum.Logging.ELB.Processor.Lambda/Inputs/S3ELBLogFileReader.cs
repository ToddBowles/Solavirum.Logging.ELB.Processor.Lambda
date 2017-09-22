using System.Collections.Generic;
using System.IO;
using Amazon.S3;

namespace Solavirum.Logging.ELB.Processor.Lambda.Inputs
{
	public class S3ELBLogFileReader : IELBLogFileReader
	{
		public S3ELBLogFileReader(AmazonS3Client client, string bucket, string key)
		{
			_client = client;
			_bucket = bucket;
			_key = key;
		}

		private readonly AmazonS3Client _client;
		private readonly string _bucket;
		private readonly string _key;

		public IEnumerable<string> Lines()
		{
			var getObjectTask = _client.GetObjectAsync(_bucket, _key);
			getObjectTask.Wait();
			if (getObjectTask.IsFaulted)
			{
				throw getObjectTask.Exception;
			}

			using (var sr = new StreamReader(getObjectTask.Result.ResponseStream))
			{
				while (!sr.EndOfStream)
				{
					yield return sr.ReadLine();
				}
			}
		}
	}
}