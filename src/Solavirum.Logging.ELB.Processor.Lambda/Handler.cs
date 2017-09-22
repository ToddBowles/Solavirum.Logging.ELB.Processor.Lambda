using System;
using System.Collections.Generic;
using System.Linq;
using Amazon;
using Amazon.Lambda.Core;
using Amazon.S3;
using Microsoft.Extensions.Configuration;
using Newtonsoft.Json;
using Solavirum.Logging.ELB.Processor.Lambda.Inputs;
using Solavirum.Logging.ELB.Processor.Lambda.Logging;
using Solavirum.Logging.ELB.Processor.Lambda.Outputs;
using Solavirum.Logging.ELB.Processor.Lambda.Processing;
using LambdaLogger = Solavirum.Logging.ELB.Processor.Lambda.Logging.LambdaLogger;

namespace Solavirum.Logging.ELB.Processor.Lambda
{
	public class Handler
    {
	    /// <summary>
		/// Only used for Lambda execution.
		/// </summary>
	    public Handler()
	    {
		    _configurationOverrides = null;
		    _logger = new LambdaLogger();
	    }

	    public Handler(ILogger logger, IEnumerable<KeyValuePair<string, string>> configurationOverrides)
	    {
		    _logger = logger;
		    _configurationOverrides = configurationOverrides;
	    }

	    private readonly ILogger _logger;
	    private readonly IEnumerable<KeyValuePair<string, string>> _configurationOverrides;

	    [LambdaSerializer(typeof(Amazon.Lambda.Serialization.Json.JsonSerializer))]
		public void Handle(Amazon.Lambda.S3Events.S3Event e)
        {
			var builder = new ConfigurationBuilder()
				.AddJsonFile("Configuration/config.json");

	        if (_configurationOverrides != null)
	        {
		        builder.AddInMemoryCollection(_configurationOverrides);
	        }

			var config = builder.Build();

			_logger.Log($"Processing ELB log file from [{e?.Records?.First()?.S3?.Bucket?.Name ?? "null-bucket"}:{e?.Records?.First()?.S3?.Object?.Key ?? "null-key"}]");

	        if (e.Records.Count > 1)
	        {
		        var s3ObjectSummary = string.Join(", ", e.Records.Select(a => $"[{a?.S3?.Bucket?.Name ?? "null-bucket"}:{a?.S3?.Object?.Key ?? "null-key"}]"));
		        throw new InvalidOperationException($"The supplied S3Event contained multiple S3 records. This function will only process a single record. Records were {s3ObjectSummary}");
	        }

	        var message = e.Records.Single();

	        var s3Client = new AmazonS3Client(new AmazonS3Config { RegionEndpoint = RegionEndpoint.GetBySystemName(message.AwsRegion)});
	        var input = new S3ELBLogFileReader(s3Client, message.S3.Bucket.Name, message.S3.Object.Key);
	        var output = new HttpLogstashOutput(config[Configuration.Keys.Logstash_Url]);
	        var fields = new LogEventFactory
			(
				environment: config[Configuration.Keys.Event_Environment],
		        application: config[Configuration.Keys.Event_Application],
		        component: config[Configuration.Keys.Event_Component],
		        sourceModuleName: config[Configuration.Keys.Event_SourceModuleName],
				type: config[Configuration.Keys.Event_Type]
			);

	        var processor = new Engine(_logger, input, output, fields);
	        var stats = processor.Execute();

	        _logger.Log("All processing complete. Summary follows:");
			_logger.Log(JsonConvert.SerializeObject(stats));
        }
    }
}
