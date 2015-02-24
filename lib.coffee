Promise = require 'bluebird'
fs = Promise.promisifyAll(require('fs'))
cp = Promise.promisifyAll(require('child_process'))
CombinedStream = require 'combined-stream'

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

# Replace the contents of a partition.
# 
# Parameters:
# path: Path to disk image file.
# partitionNumber: Index of the partition to be replaced.
# data: string or buffer with the new contents of the partition.
# 
# If data length is less than partition size, it will be padded with zeros.
#
# Returns a promise that resolves into a stream with the new disk contents.
exports.replacePartition = replacePartition = (path, partitionNumber, data) ->
	if typeof data isnt 'string' and not Buffer.isBuffer(data)
		throw new TypeError('Parameter data should be string or buffer')
	getPartitionInfo(path, partitionNumber)
	.then (partition) ->
		if typeof data is 'string'
			data = new Buffer(data)
		if data.length > partition.size
			throw new RangeError('Contents should not be larger than partition size.')

		combinedStream = CombinedStream.create()
		combinedStream.append fs.createReadStream path,
			start: 0 
			end: partition.start - 1
		combinedStream.append(data)
		if partition.size > data.length
			combinedStream.append fs.createReadStream '/dev/zero',
				start: 0
				end: partition.size - data.length - 1
		combinedStream.append fs.createReadStream path,
			start: partition.end + 1
		return combinedStream
