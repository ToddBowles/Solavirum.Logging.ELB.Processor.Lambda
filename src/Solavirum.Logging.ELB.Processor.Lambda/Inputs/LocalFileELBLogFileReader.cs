using System.Collections.Generic;
using System.IO;

namespace Solavirum.Logging.ELB.Processor.Lambda.Inputs
{
	public class LocalFileELBLogFileReader : IELBLogFileReader
	{
		public LocalFileELBLogFileReader(string path)
		{
			_path = path;
		}

		private readonly string _path;

		public IEnumerable<string> Lines()
		{
			using (var fs = System.IO.File.OpenRead(_path))
			using (var sr = new StreamReader(fs))
			{
				while (!sr.EndOfStream) yield return sr.ReadLine();
			}
		}
	}
}