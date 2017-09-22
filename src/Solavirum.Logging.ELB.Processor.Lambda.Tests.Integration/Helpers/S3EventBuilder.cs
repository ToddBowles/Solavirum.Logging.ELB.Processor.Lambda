using System;
using System.Collections.Generic;
using Amazon;
using Amazon.Lambda.S3Events;
using Amazon.S3.Util;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Helpers
{
	public class S3EventBuilder
	{
		private string _bucket = Guid.NewGuid().ToString();
		private string _key = Guid.NewGuid().ToString();
		private readonly RegionEndpoint _region = RegionEndpoint.APSoutheast2;

		public S3EventBuilder ForS3Object(string bucket, string key)
		{
			_bucket = bucket;
			_key = key;
			return this;
		}

		public S3Event Build()
		{
			var e = new S3Event
			{
				Records = new List<S3EventNotification.S3EventNotificationRecord>
				{
					new S3EventNotification.S3EventNotificationRecord
					{
						AwsRegion = _region.SystemName,
						EventTime = DateTime.Now,
						S3 = new S3EventNotification.S3Entity
						{
							Bucket = new S3EventNotification.S3BucketEntity
							{
								Name = _bucket
							},
							Object = new S3EventNotification.S3ObjectEntity
							{
								Key = _key
							}
						}
					}
				}
			};

			return e;
		}
	}
}