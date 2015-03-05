Promise = require 'bluebird'
fs = Promise.promisifyAll(require('fs'))
cp = Promise.promisifyAll(require('child_process'))
CombinedStream = require 'combined-stream'
{ Stream } = require 'stream'
es = require 'event-stream'

# Parse the MBR of a disk.
# Return an array of objects with information about each partition.
# Bytes are used as units.
exports.parseMBR = parseMBR = (path) ->
	cp.execAsync("parted -s -m #{path} unit B print")
	.then (stdout, stderr) ->
		stdout.toString().split('\n')[2..]
	.map (line) ->
		info = line.split(':')

		number: info[0]
		start: parseInt(info[1])
		end: parseInt(info[2])
		size: parseInt(info[3])
		fs: info[4]
		name: info[5]
		flags: info[6]

# Get information about a partition of a disk.
#
# Parameters:
# path: the path to .img file
# partitionNumber: the index of partition
#
# For details about the result see MBR.Partition class of 'mbr' module.
getPartitionInfo = (path, partitionNumber) ->
	parseMBR(path)
	.then (mbr) ->
		if not mbr[partitionNumber]?
			throw new RangeError('Disk does not have such partition.')
		return mbr[partitionNumber]

# Create a stream from the given data that will pipe an output of a specific size.
#
# If less data are piped, zeros are added to the stream.
# If more data are piped, the extra data are ignored and an error event is sent.
# Data can be a buffer or a stream.
createFixedSizeStream = (input, size, opts = {}) ->
	fixedStream = CombinedStream.create()
	pipedLength = 0
	fixedStream.append (next) ->
		if Buffer.isBuffer(input)
			thestream = es.through().pause().queue(input).end()
		else
			thestream = input
		next thestream.pipe es.mapSync (buf) ->
			console.log('piped', buf, pipedLength, buf.length + pipedLength, size)
			if size <= pipedLength
				return ""
			if size < buf.length + pipedLength
				offset = size - pipedLength
				pipedLength = size
				if opts.overflowCallback
					opts.overflowCallback(buf.slice(offset))
				return buf.slice(0, offset)
			else
				pipedLength += buf.length
				return buf
	fixedStream.append (next) ->
		remainingLength = size - pipedLength
		console.log('rem', remainingLength, size, pipedLength)
		if remainingLength > 0
			next fs.createReadStream '/dev/zero',
				start: 0
				end: remainingLength - 1
		else
			next(CombinedStream.create())

# Replace the contents of a partition.
# 
# Parameters:
# path: Path to disk image file.
# partitionNumber: Index of the partition to be replaced.
# data: string, buffer or stream with the new contents of the partition.
# 
# If data length is less than partition size, it will be padded with zeros.
# Warning: if data is a stream, the caller is responsible for it to
# cover the whole size of the partition.
#
# Returns a promise that resolves into a stream with the new disk contents.
exports.replacePartition = replacePartition = (path, partitionNumber, data) ->
	Promise.try ->
		if typeof data isnt 'string' and not Buffer.isBuffer(data) and not data instanceof Stream and not typeof data == 'function'
			throw new TypeError('Parameter data should be string or buffer')
		if typeof partitionNumber != 'number'
			throw new TypeError('Parameter partitionNumber should be a number.')
		getPartitionInfo(path, partitionNumber)
		.then (partition) ->
			if typeof data is 'string'
				data = new Buffer(data)
			if Buffer.isBuffer(data) and data.length > partition.size
				throw new RangeError('Contents should not be larger than partition size.')
			console.log('positions', partition.start - 1, partition.end + 1)

			combinedStream = CombinedStream.create()
			combinedStream.append fs.createReadStream path,
				start: 0 
				end: partition.start - 1
			combinedStream.append(createFixedSizeStream(data, partition.size))
			combinedStream.append fs.createReadStream path,
				start: partition.end + 1
			return combinedStream
