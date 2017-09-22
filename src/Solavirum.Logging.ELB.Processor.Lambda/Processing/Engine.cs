using System;
using System.Linq;
using Solavirum.Logging.ELB.Processor.Lambda.Inputs;
using Solavirum.Logging.ELB.Processor.Lambda.Logging;
using Solavirum.Logging.ELB.Processor.Lambda.Outputs;

namespace Solavirum.Logging.ELB.Processor.Lambda.Processing
{
	public class Engine
	{
		public Engine(ILogger logger, IELBLogFileReader input, ILogstashOutput output, LogEventFactory factory)
		{
			_logger = logger;
			_input = input;
			_output = output;
			_factory = factory;
		}

		private readonly ILogger _logger;
		private readonly IELBLogFileReader _input;
		private readonly ILogstashOutput _output;
		private readonly LogEventFactory _factory;

		public ProcessStatistics Execute()
		{
			var result = _input
				.Lines()
				.AsParallel()
				.Select(a => _factory.Make(a))
				.Select(TrySend)
				.ToList();

			return new ProcessStatistics
			{
				Lines = new LinesStatistics
				{
					Encountered = result.Count,
					Sent = result.Where(a => a.OK).Count()
				},
				Failures = new FailureStatisticsCollection
				{
					Sending = new FailureStatistics
					{
						Total = result.Where(a => !a.OK).Count(),
						LastFew = result.Where(a => !a.OK).Reverse().Take(10).Select(a => a.Error).ToArray()
					}
				}
			};
		}

		private SendResult TrySend(LogEvent e)
		{
			try
			{
				_output.Send(e);
				return SendResult.Success();
			}
			catch (Exception ex)
			{
				return SendResult.Failure(ex);
			}
		}

		private class SendResult
		{
			public static SendResult Success()
			{
				return new SendResult(true, null);
			}

			public static SendResult Failure(Exception ex)
			{
				return new SendResult(false, ex);
			}

			private SendResult(bool success, Exception error)
			{
				OK = success;
				Error = error;
			}

			public readonly bool OK;
			public readonly Exception Error;
		}
	}
}