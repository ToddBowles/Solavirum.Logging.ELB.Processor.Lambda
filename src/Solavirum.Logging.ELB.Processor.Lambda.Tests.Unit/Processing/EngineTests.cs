using System;
using System.Linq;
using FluentAssertions;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Solavirum.Logging.ELB.Processor.Lambda.Inputs;
using Solavirum.Logging.ELB.Processor.Lambda.Logging;
using Solavirum.Logging.ELB.Processor.Lambda.Outputs;
using Solavirum.Logging.ELB.Processor.Lambda.Processing;
using Solavirum.Logging.ELB.Processor.Lambda.Tests.Unit.Helpers;
using Xunit;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Unit.Processing
{
    public class EngineTests
    {
        [Fact]
        public void WhenNoLinesAvailableThroughInput_OutputRecordsNoActivity_AndStatsShowTheSame()
        {
            var logger = new InMemoryLogger();
            var input = Substitute.For<IELBLogFileReader>();
            input.Lines().Returns(Enumerable.Empty<string>());

            var output = Substitute.For<ILogstashOutput>();

            var engine = new Engine(logger, input, output, new LogEventFactoryBuilder().Build());
            var stats = engine.Execute();

            output.DidNotReceive().Send(Arg.Any<LogEvent>());

            stats.Lines.Encountered.Should().Be(0);
            stats.Lines.Sent.Should().Be(0);
            stats.Failures.Sending.LastFew.Should().BeEmpty();
            stats.Failures.Sending.Total.Should().Be(0);
        }

        [Fact]
        public void WhenThereAreSomeLinesAvailableThroughInput_OutputRecordsAppropriateActivity_AndStatsShowCorrectValues()
        {
            var logger = new InMemoryLogger();
            var input = Substitute.For<IELBLogFileReader>();
            input.Lines().Returns(new[] { "first_line", "second_line" });

            var output = Substitute.For<ILogstashOutput>();

            var engine = new Engine(logger, input, output, new LogEventFactoryBuilder().Build());
            var stats = engine.Execute();

            output.Received(2).Send(Arg.Any<LogEvent>());

            stats.Lines.Encountered.Should().Be(2);
            stats.Lines.Sent.Should().Be(2);
            stats.Failures.Sending.LastFew.Should().BeEmpty();
            stats.Failures.Sending.Total.Should().Be(0);
        }

        [Fact]
        public void WhenThereAreSomeLinesAvailableThroughInput_ButOutputFailsOnASpecificInput_StatsShowFailure()
        {
            var logger = new InMemoryLogger();
            var input = Substitute.For<IELBLogFileReader>();
            input.Lines().Returns(new[] { "first_line", "second_line" });

            var output = Substitute.For<ILogstashOutput>();
            output.Send(Arg.Is<LogEvent>(a => a.message == "second_line")).Throws(new InvalidOperationException("This message fails to send"));

            var engine = new Engine(logger, input, output, new LogEventFactoryBuilder().Build());
            var stats = engine.Execute();

            output.Received(2).Send(Arg.Any<LogEvent>());

            stats.Lines.Encountered.Should().Be(2);
            stats.Lines.Sent.Should().Be(1);
            stats.Failures.Sending.LastFew.Should().NotBeEmpty();
            stats.Failures.Sending.Total.Should().Be(1);
        }

        [Fact]
        public void WhenThereAreSomeLinesAvailableThroughInput_AndThereAreManyFailures_StatsOnlyContainsASubsetOfFailures()
        {
            var logger = new InMemoryLogger();
            var input = Substitute.For<IELBLogFileReader>();
            input.Lines().Returns(Enumerable.Range(1, 100).Select(a => a.ToString()));

            var output = Substitute.For<ILogstashOutput>();
            output.Send(Arg.Any<LogEvent>()).Throws(new InvalidOperationException("This message fails to send"));

            var engine = new Engine(logger, input, output, new LogEventFactoryBuilder().Build());
            var stats = engine.Execute();

            stats.Lines.Encountered.Should().Be(100);
            stats.Lines.Sent.Should().Be(0);
            stats.Failures.Sending.LastFew.Length.Should().Be(10);
            stats.Failures.Sending.Total.Should().Be(100);
        }
    }
}

