Promise = require 'bluebird'
MBR = require 'mbr'
fs = Promise.promisifyAll(require('fs'))
CombinedStream = require 'combined-stream'

# Parse the MBR of a disk.
# For details about the result of parsing see 'mbr' module.
parseMBR = (path) ->
	fs.openAsync(path, 'r+')
	.then (fd) ->
		buffer = new Buffer(512)
		fs.readAsync(fd, buffer, 0, 512, 0)
	.spread (bytesRead, buffer) ->
		if bytesRead isnt 512
			throw new Error('Could not read 512 bytes from disk file.')
		new MBR(buffer)

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
		if not mbr.partitions[partitionNumber]?
			throw new RangeError('Disk does not have such partition.')
		return mbr.partitions[partitionNumber]

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
		partitionSize = partition.sectors * 512
		if typeof data is 'string'
			data = new Buffer(data)
		if data.length > partitionSize
			throw new RangeError('Contents should not be larger than partition size.')

		firstByte = partition.firstLBA * 512

		combinedStream = CombinedStream.create()
		combinedStream.append fs.createReadStream path,
			start: 0 
			end: firstByte - 1
		combinedStream.append(data)
		if partitionSize > data.length
			combinedStream.append fs.createReadStream '/dev/zero',
				start: 0
				end: partitionSize - data.length - 1
		combinedStream.append fs.createReadStream path,
			start: firstByte + partitionSize
		return combinedStream
