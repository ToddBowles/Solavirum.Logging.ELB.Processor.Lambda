'use strict';

exports.make = (type) => {
    return function (event, context, callback) {
        let AWS = require('aws-sdk');
        let net = require('net');
        let gPool = require('generic-pool');

        let summary = {
            lines: {
                encountered: 0,
                parsed: 0,
                sent: 0
            },
            connections: {
                created: 0,
                destroyed: 0
            },
            failures: {
                parsing: {
                    total: 0,
                    lastFew: []
                },
                sending: {
                    total: 0,
                    lastFew: []
                }
            }
        };

        let promises = [];

        let configFileName = "debug.json"
        if (type == "octopus") {
            configFileName = "octopus.json";
        }

        var configPath = "./config/" + configFileName;
        let config = require(configPath);

        const poolFactory = {
            create: function() {
                return new Promise(function(resolve, reject) {
                    const socket = net.createConnection(config.logstashPort, config.logstashHost);
                    summary.connections.created += 1;
                    resolve(socket);
                })
            },
            destroy: function(socket) {
                return new Promise(function(resolve, reject) {
                    socket.end();
                    socket.destroy();
                    summary.connections.destroyed += 1;
                    resolve();
                })
            },
            validate: function(socket) {
                return new Promise(function(resolve, reject){
                    resolve(!socket.destroyed);
                })
            }
        };

        var poolOptions = {
            max: config.connectionCountLimit,
            min: 0,
            acquireTimeoutMillis: config.connectionWaitMilliseconds,
            testOnBorrow: true
        };

        var pool = gPool.createPool(poolFactory, poolOptions);

        const readline = require('readline');
        const S3 = new AWS.S3({ apiVersion: '2006-03-01' });

        function post(socket, entry) {
            return new Promise(function(resolve, reject) {
                var message = JSON.stringify(entry) + "\n";
                message = message.replace("Timestamp", "@timestamp");
                socket.write(message, null);

                summary.lines.sent += 1;

                resolve(socket);
            });
        }

        function parse_url(url) {
            var pattern = RegExp("^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?");
            var matches = url.match(pattern);
            return {
                scheme: matches[2],
                authority: matches[4],
                path: matches[5],
                query: matches[7],
                fragment: matches[9]
            };
        }

        let s3FileDetails;

        function fixStringifyError(key, value) {
            if (value instanceof Error) {
                var error = {};

                Object.getOwnPropertyNames(value).forEach(function (key) {
                    error[key] = value[key];
                });

                return error;
            }

            return value;
        }

        String.prototype.format = function () {
            var args = arguments;
            return this.replace(/\{\{|\}\}|\{(\d+)\}/g, function (m, n) {
                if (m == "{{") { return "{"; }
                if (m == "}}") { return "}"; }
                return args[n];
            });
        };

        function handleLine(line) {
            summary.lines.encountered += 1;

            const columns = line.split(/ (?=(?:(?:[^"]*"){2})*[^"]*$)/);
            const splitRequest = columns[11].split(/[ "]+/);
            var url = parse_url(splitRequest[2])

            // There are 15 total columns in an ELB log line, but we only care about the first 13. 
            // We still validate on the full 15 though.
            const expectedColumns = 15;

            if (columns.length == expectedColumns) {
                var entry = {
                    Timestamp: columns[0],
                    LoadBalancerName: columns[1],
                    PublicIpAndPort: columns[2],
                    InternalIpAndPort: columns[3],
                    Status: columns[7],
                    BackendStatus: columns[8],
                    BytesUploadedFromClient: parseInt(columns[9]),
                    BytesDownloadedByClient: parseInt(columns[10]),
                    Component: config.component,
                    SourceModuleName: config.sourceModuleName,
                    Environment: config.environment,
                    Application: config.application,
                    UserAgent: columns[12],
                    message: line,
                    type: config.type,
                    Verb: splitRequest[1],
                    Path: url.path,
                    Source: {
                        S3: s3FileDetails
                    }
                };

                var TimeToForwardRequest = parseFloat(columns[4]);
                if (TimeToForwardRequest !== -1) {
                    entry.TimeToForwardRequest = Math.round(TimeToForwardRequest * 1000);
                }

                var TimeTaken = parseFloat(columns[5]);
                if (TimeTaken !== -1) {
                    entry.TimeTaken = Math.round(TimeTaken * 1000);
                }

                var TimeToForwardResponse = parseFloat(columns[6]);
                if (TimeToForwardResponse !== -1) {
                    entry.TimeToForwardResponse = Math.round(TimeToForwardResponse * 1000);
                }

                summary.lines.parsed += 1;
                
                var promise = pool.acquire()
                    .then((socket) => { return post(socket, entry); })
                    .then((socket) => { pool.release(socket); })
                    .catch((error) => { 
                        summary.failures.sending.total += 1;
                        if (summary.failures.sending.lastFew.length >= 5) {
                            summary.failures.sending.lastFew.shift();
                        }
                        summary.failures.sending.lastFew.push(error);
                    });

                promises.push(promise);
            } 
            else {
                var message = "Line was parsed into an unexpected number of columns. Was expecting [{0}] columns, but found [{1}]".format(expectedColumns, columns.length);
                summary.failures.parsing.total += 1;
                var columnMismatch = {
                    message: message,
                    line: line
                };
                if (summary.failures.parsing.lastFew.length >= 5) {
                    summary.failures.parsing.lastFew.shift();
                }
                summary.failures.parsing.lastFew.push(columnMismatch);
            }
        }

        function handleReaderClose() {
            console.log('File reader for ELB log file is closing because all lines have been read. Waiting for all promises (for sending parsed lines to logstash) to resolve');
            Promise
                .all(promises)
                .then(() => { console.log("Cleaning up the connection pool, which has [%s/%s] (current/max) connections", pool.size, pool.max); return pool.drain(); })
                .then(() => pool.clear())
                .then(() => { 
                    console.log("All processing complete. Summary follows"); 
                    console.log("%s", JSON.stringify(summary, fixStringifyError, 4)); 
                });
        }
        
        const bucket = event.Records[0].s3.bucket.name;
        const key = decodeURIComponent(event.Records[0].s3.object.key.replace(/\+/g, ' '));
        s3FileDetails = {
            Bucket: bucket,
            Key: key
        };

        console.log('Retrieving ELK log file from S3 bucket/key specified in the initiating event. Bucket: [%s], Key: [%s]', s3FileDetails.Bucket, s3FileDetails.Key);

        const reader = readline.createInterface({
            input: S3.getObject(s3FileDetails).createReadStream()
        });

        reader
            .on('line', handleLine)
            .on('close', handleReaderClose);
    };
}