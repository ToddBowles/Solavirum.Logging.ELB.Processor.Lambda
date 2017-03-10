'use strict';

let AWS = require('aws-sdk');
let net = require('net');

const _type = 'logs';
const _sourceModuleName = 'ELB';
const _logHost = '#{LogHost}';
const _logPort = #{LogPort};
const _environment = '#{Octopus.Environment.Name}';
const _component = '#{Component}';
const _application = '#{Application}';
const connectionCountLimit = #{ConnectionCountLimit};
const waitForConnectionDuration = #{WaitForConnectionDuration};

let connectionPool = [];
let _params;
let stats = {
    parsed: 0,
    sent: 0
};

function getConnection(callback) {
    if (connectionPool.length < connectionCountLimit) {
        console.log('The current size of the connection pool is less than the limit (%s < %s). Creating a new connection', connectionPool.length, connectionCountLimit);
        const newSocket = net.createConnection(_logPort, _logHost);
        connectionPool.push(newSocket);
        return callback(newSocket);
    }

    const activeConnections = connectionPool.filter(function (socket) {
        return !socket.destroyed;
    });
    if (activeConnections.length != connectionCountLimit) {
        connectionPool = activeConnections;
    }

    setTimeout(function () {
        getConnection(callback);
    }, waitForConnectionDuration);
}

function postToLogstash(connection) {
    return function (entry) {
        var message = JSON.stringify(entry) + "\n";
        message = message.replace("Timestamp", "@timestamp");
        connection.write(message, null, function () {
            stats.sent += 1;
            connection.end();
        });
    }
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

function parseLine(line) {
    const columns = line.split(/ (?=(?:(?:[^"]*"){2})*[^"]*$)/);
    const splitRequest = columns[11].split(/[ "]+/);
    var url = parse_url(splitRequest[2])

    stats.parsed += 1;
    
    const expectedColumns = 12;

    if (columns.length >= expectedColumns) {
        var entry = {
            Timestamp: columns[0],
            LoadBalancerName: columns[1],
            PublicIpAndPort: columns[2],
            InternalIpAndPort: columns[3],
            Status: columns[7],
            BackendStatus: columns[8],
            BytesUploadedFromClient: parseInt(columns[9]),
            BytesDownloadedByClient: parseInt(columns[10]),
            Component: _component,
            SourceModuleName: _sourceModuleName,
            Environment: _environment,
            Application: _application,
            message: line,
            type: _type,
            Verb: splitRequest[1],
            Path: url.path,
            Source: {
                S3: _params
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

        getConnection(function (connection) {
            postToLogstash(connection)(entry)
        });

    } else {
        console.error("Line was parsed into an unexpected number of columns. Was expecting [%s] columns, but found [%s]. Raw line was [%s]", expectedColumns.length, columns.length, line);
    }
}

function handleReaderClose() {
    console.log('File reader for ELB log file is closing. Parsed [%s], Sent To Logstash [%s]', stats.parsed, stats.sent);
}

exports.handler = (event, context, callback) => {
    const readline = require('readline');
    const S3 = new AWS.S3({ apiVersion: '2006-03-01' });

    console.log('Retrieving ELK log file from S3 bucket/key specified in the initiating event');

    const bucket = event.Records[0].s3.bucket.name;
    const key = decodeURIComponent(event.Records[0].s3.object.key.replace(/\+/g, ' '));
    _params = {
        Bucket: bucket,
        Key: key
    };

    const reader = readline.createInterface({
        input: S3.getObject(_params).createReadStream()
    });

    reader
        .on('line', parseLine)
        .on('close', handleReaderClose);
};
