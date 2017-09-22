using System;
using System.Net.Http;
using System.Text;
using Newtonsoft.Json;
using Solavirum.Logging.ELB.Processor.Lambda.Processing;

namespace Solavirum.Logging.ELB.Processor.Lambda.Outputs
{
	public class HttpLogstashOutput : ILogstashOutput
	{
		public HttpLogstashOutput(string logstashUrl)
		{
			_client = new HttpClient {BaseAddress = new Uri(logstashUrl)};
		}

		private HttpClient _client;

		public bool Send(LogEvent e)
		{
			var json = JsonConvert.SerializeObject(e);
			var post = _client.PostAsync(string.Empty, new StringContent(json, Encoding.UTF8, "application/json"));
			return post.Result != null && post.Result.IsSuccessStatusCode;
		}
	}
}