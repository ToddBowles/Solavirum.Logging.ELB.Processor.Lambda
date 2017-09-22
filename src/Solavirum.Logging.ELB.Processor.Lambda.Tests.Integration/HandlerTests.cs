using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using FluentAssertions;
using Microsoft.DotNet.PlatformAbstractions;
using Newtonsoft.Json;
using Solavirum.Logging.ELB.Processor.Lambda.Logging;
using Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Helpers;
using Xunit;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration
{
    public class HandlerTests
    {
        /// <summary>
        /// This test is reliant on an AWS profile being setup with the name "elb-processor-s3-test" that has permissions
        /// to create and delete S3 buckets with prefixes bucket-prefix. and read items in those buckets
        /// </summary>
        [Fact]
        public void WhenHandlingAValidS3Event_ConnectsToS3ToDownloadTheFile_AndOutputsEventsToLogstash()
        {
            var logger = new InMemoryLogger();
            var application = Guid.NewGuid().ToString();
            var config = new Dictionary<string, string>
            {
                { Configuration.Keys.Event_Environment, Guid.NewGuid().ToString() },
                { Configuration.Keys.Event_Application, application},
                { Configuration.Keys.Event_Component, Guid.NewGuid().ToString() },
                { Configuration.Keys.Logstash_Url, "http://a-logstash-broker.com" }
            };
            using (AWSProfileContext.New("elb-processor-s3-test"))
            {
                var s3 = new AmazonS3Client(new AmazonS3Config { RegionEndpoint = RegionEndpoint.APSoutheast2 });
                var testBucketManager = new TestS3BucketManager(s3, "bucket-prefix.");
                using (var bucket = testBucketManager.Make())
                {
                    var templateFile = Path.Combine(ApplicationEnvironment.ApplicationBasePath, @"Helpers\Data\CloudSyncApi-small-sample.log");
                    var altered = File.ReadAllText(templateFile).Replace("@@TIMESTAMP", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ"));
                    var stream = new MemoryStream(Encoding.UTF8.GetBytes(altered));
                    var putResult = s3.PutObjectAsync(new PutObjectRequest { BucketName = bucket.Name, InputStream = stream, Key = "test-file" }).Result;

                    var message = new S3EventBuilder().ForS3Object(bucket.Name, "test-file").Build();

                    var handler = new Handler(logger, config);
                    handler.Handle(message);
                }
            }

            // Check that there are some events in Elasticsearch with our Application
            Func<long> query = () =>
            {
                var client = new HttpClient {BaseAddress = new Uri("http://an-elasticsearch-cluster:9200")};
                var raw = client.GetStringAsync($"/logstash-*/_search?q=Application:{application}").Result;
                dynamic result = JsonConvert.DeserializeObject(raw);
                return (long) result.hits.total;
            };

            query.ResultShouldEventuallyBe(hits => hits.Should().BeGreaterThan(0, $"because there should be some documents in Elasticsearch with Application:{application}"));
        }
    }
}
