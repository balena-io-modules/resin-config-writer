es = require 'event-stream'
fs = require 'fs'

# Create a through stream that ensures a certain output size is not underflowed.
# If the size is not reached, the stream is filled with zeros.
exports.underflowStream = underflowStream = (size) ->
	pipedLength = 0
	es.through(
		(data) ->
			pipedLength += data.length
			@emit('data', data)
		(data) ->
			if pipedLength < size
				zeroStream = fs.createReadStream '/dev/zero', 
					start: 0
					end: size - pipedLength - 1
				zeroStream.on 'data', (data) =>
					@emit('data', data)
				zeroStream.on('end', => @emit('end'))
			else
				@emit('end')
	)

# Create a through stream that ensures a certain output size is not overflowed.
# If the size is passed, an error event is emitted.
exports.overflowStream = overflowStream = (size) ->
	pipedLength = 0
	es.through (data) ->
		if size < pipedLength + data.length
			offset = size - pipedLength
			data = data.slice(0, offset)
			pipedLength = size
			@emit('data', data)
			@emit('error', new RangeError('Stream overflowed'))
		else
			pipedLength += data.length
			@emit('data', data)


# Create a stream that will pass through data of a specific size.
#
# If less data are piped to it, zeros are added to the stream.
# If more data are piped to it, the extra data are ignored and an error event is sent.
exports.fixedSizeStream = (size) ->
	es.pipe(underflowStream(size), overflowStream(size))

