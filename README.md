# What is this?
This project is an AWS Lambda function to facilitate log aggregation.

Logs are read from an S3 bucket (via bucket notifications), processed line by line and then written to a Logstash endpoint such that they end up in Elasticsearch.

# How do I develop?
Lets assume you've checked this repo out locally.

You'll need Node first obviously. AWS Lambda only runs version 4.3.2, so thats fun. The appropriate version of node is included in this respository, so if you want to use the command line directly you will need to include it in your path.

From a normal Windows command line this looks like the following:

```
cd C:\dev\Solavirum.Logging.ELB.Processor.Lambda\
SET PATH=%CD%\tools\node-x64-4.3.2\;%PATH%
```

It's recommended to use Visual Studio Code to debug, as this repository features a launch.json file and some helper scripts to allow you to seamlessly debug with a known version of Node.

## Step-by-Step (VSCode)
1. Place your breakpoints in the javascript files however you want
2. Select the **Launch via NPM" option
3. Hit F5 to start the debugger defined in launch.json
4. If all goes well, it should have hit your breakpoints

# How do I deploy?
A Nuget package is built from this repository and then published to Octopus. This package contains a deploy.ps1 file which is responsible for uploading the actual code to a Lambda function.

In order to do this it uses some Octopus variables, most importantly AWS.Lambda.Function.Name to determine where its actually going to publish the code to.

## Infrastructure
Because this is a Lambda function you will need to have a Lambda function setup in AWS. You'll also need an S3 bucket and event notification setup between the two.

### Lambda function
This lambda function must be able to execute the code  
This lambda function must have access to objects in s3  
This lambda function must have access to logs  
This lambda function must have access to network resource (i.e. vcp)  

Permissions are generally setup via roles as part of the environment configuration (i.e. CloudFormation).

### S3 Logs Bucket
This bucket will receive logs from an ELB
This bucket will be configured to send event notification to the lambda function  

# Who is responsible for this terrible thing?
While the repo lives under the Github account of [Todd Bowles](https://github.com/ToddBowles), and he was a primary contributor, this function could not have been created without the efforts of Jerry Mooyman and Robbie Bergan. When they give me some links to their online presence, I'll put proper links in here.