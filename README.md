# What is this?
This project is an AWS Lambda function to facilitate log aggregation.

Logs are read from an S3 bucket (via bucket notifications), processed line by line and then written to a Logstash endpoint such that they end up in Elasticsearch.

# How do I develop?
It's NET Core now. Thank god. Javascript/Node are terrible.

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

# Notes
This is a sanitized clone of an internal repository, and as such it might not quite work. Its intended to be used primarily as a reference to accompany the blog post [here](http://www.codeandcompost.com/post/aws-lambda-and-.net-core,-two-great-tastes-that-taste-great-together,-part-4).

# Who is responsible for this terrible thing?
While the repo lives under the Github account of [Todd Bowles](https://github.com/ToddBowles), and he was a primary contributor, this function could not have been created without the efforts of Jerry Mooyman and Robbie Bergan. When they give me some links to their online presence, I'll put proper links in here.  