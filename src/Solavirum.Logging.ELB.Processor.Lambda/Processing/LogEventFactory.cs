namespace Solavirum.Logging.ELB.Processor.Lambda.Processing
{
	public class LogEventFactory
	{
		public LogEventFactory(string environment, string application, string component, string sourceModuleName, string type)
		{
			Environment = environment;
			Application = application;
			Component = component;
			SourceModuleName = sourceModuleName;
			Type = type;
		}

		public string Environment { get; }
		public string Application { get; }
		public string Component { get; }
		public string SourceModuleName { get; }
		public string Type { get; }

		public LogEvent Make(string message)
		{
			return new LogEvent
			{
				Environment = Environment,
				Application = Application,
				Component = Component,
				SourceModuleName = SourceModuleName,
				type = Type,
				message = message
			};
		}
	}

	public class LogEvent
	{
		public string Environment { get; set; }
		public string Application { get; set; }
		public string Component { get; set; }
		public string SourceModuleName { get; set; }
		public string type { get; set; }
		public string message { get; set; }
	}
}