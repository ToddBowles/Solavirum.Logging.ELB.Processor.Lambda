using FluentAssertions;
using Microsoft.DotNet.PlatformAbstractions;
using Solavirum.Logging.ELB.Processor.Lambda.Inputs;
using Solavirum.Logging.ELB.Processor.Lambda.Logging;
using Solavirum.Logging.ELB.Processor.Lambda.Outputs;
using Solavirum.Logging.ELB.Processor.Lambda.Processing;
using Solavirum.Logging.ELB.Processor.Lambda.Tests.Unit.Helpers;
using System.IO;
using Xunit;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Processing
{
    public class EngineTests
    {
        [Fact]
        public void WhenUsingARealLocalFileAsInput_CorrectlyReadsAllLinesInFileAndPostsThemToLogstash()
        {
            var logger = new InMemoryLogger();
            var input = new LocalFileELBLogFileReader(Path.Combine(ApplicationEnvironment.ApplicationBasePath, @"Helpers\Data\CloudSyncApi-large-sample.log"));
            var output = new InMemoryLogstashOutput();
            var engine = new Engine(logger, input, output, new LogEventFactoryBuilder().Build());

            var stats = engine.Execute();

            stats.Lines.Encountered.Should().Be(13408);
            output.Events.Count.Should().Be(13408);
        }
    }
}
