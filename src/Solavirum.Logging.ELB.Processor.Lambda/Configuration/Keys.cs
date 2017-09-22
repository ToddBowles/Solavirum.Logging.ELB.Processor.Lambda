using System;
using System.Collections.Generic;
using System.Text;

namespace Solavirum.Logging.ELB.Processor.Lambda.Configuration
{
    public static class Keys
    {
	    public static string Logstash_Url = "Logstash:Url";
	    public static string Event_Application = "Event:Application";
	    public static string Event_Component = "Event:Component";
	    public static string Event_Environment = "Event:Environment";
	    public static string Event_SourceModuleName = "Event:SourceModuleName";
	    public static string Event_Type = "Event:Type";
	}
}
