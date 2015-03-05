Promise = require 'bluebird'
{ Stream } = require 'stream'
tmp = Promise.promisifyAll(require('tmp'))
streamToPromise = require 'stream-to-promise'
fs = require 'fs'
child_process = Promise.promisifyAll(require('child_process'))
chaiAsPromised = require 'chai-as-promised'
chai = require 'chai'
chai.use(chaiAsPromised)
es = require 'event-stream'
{ expect } = chai

writer = require '..'

streamToFile = (srcStream, destPath) ->
	destStream = fs.createWriteStream(destPath)
	return new Promise (resolve, reject) ->
		srcStream.pipe(destStream)
		srcStream.on('close', resolve)
		srcStream.on('end', resolve)
		srcStream.on('error', reject)
		srcStream.on('data', (data) -> console.log('writing', data))

createTmp = -> 
	return tmp.fileAsync().disposer ( [ tmpPath, fd, cleanup ] ) ->
		cleanup()

testReplace = (inFile, partitionNumber, contents, checksums) ->
	if contents instanceof Stream
		contentsBuffer = new Buffer(0)
		conts = contents.pipe( es.mapSync (data) ->
			contentsBuffer = Buffer.concat([contentsBuffer, data])
			return data
		)
	else
		contentsBuffer = Buffer(contents)
		conts = Buffer(contents)
	Promise.using createTmp(), child_process.execAsync("losetup -f"), writer.replacePartition(inFile, partitionNumber, conts), ( [ tmpPath ], [ loopdev ], stream ) ->
		console.log('ready')
		outFile = tmpPath
		console.log('tmpPath', tmpPath)
		outDisk = loopdev.toString().trim()
		outPartition = "#{outDisk}p3"
		streamToFile(stream, outFile)
		.then =>
			console.log('streamed')
			console.log('test0', tmpPath, loopdev)
			cmd = "losetup #{outDisk} #{outFile} && partprobe #{outDisk}"
			child_process.execAsync(cmd)
		.catch (e) ->
			console.log('test1', tmpPath, loopdev)
			console.error("Error: #{e.message}")
			console.error("Make sure you run tests with sudo")
			process.exit(1)
		.then ->
			console.log('test2', tmpPath, loopdev)
			inSize = fs.statSync(inFile).size
			outSize = fs.statSync(outFile).size
			expect(outSize).to.equal(inSize)
			fs.readFileAsync(outPartition)
		.then (data) =>
			console.log('test3', tmpPath, loopdev)
			expect(data.toString().replace(/\0/g, '')).to.equal(contentsBuffer.toString())
			return [
				child_process.execAsync("sha256sum -b #{outDisk}p1"),
				child_process.execAsync("sha256sum -b #{outDisk}p2")
			]
		.spread (p1sum, p2sum) =>
			console.log('test4', tmpPath, loopdev)
			expect(p1sum.toString().slice(0,64)).to.equal(checksums[0])
			expect(p2sum.toString().slice(0,64)).to.equal(checksums[1])
		.finally ->
			child_process.execAsync("losetup -d #{outDisk}")

describe 'replacePartition', ->
	@timeout(10000)
	before ->
		@inFile = "./test/data/test.img"
		# checksums will be used to check that other partitions are not altered
		@checksums = [ fs.readFileSync("./test/data/test.1.sha256").toString().trim(), fs.readFileSync("./test/data/test.2.sha256").toString().trim() ]
	describe.skip 'with invalid parameters', ->
		it 'should return a rejected promise', ->
			return
			expect(testReplace(@inFile, 2, @checksums)).to.be.rejectedWith(TypeError)
			expect(testReplace(@inFile, 2, {}, @checksums)).to.be.rejectedWith(TypeError)
			expect(testReplace(@inFile, null, 'test', @checksums)).to.be.rejectedWith(TypeError)
	describe.skip 'with string input', ->
		it 'replaces successfully', ->
			data = JSON.stringify({ foo: "bar", color: "red" })
			testReplace(@inFile, 2, data, @checksums)
		it 'does not allow strings larger than the partition', ->
			data = ("f" for i in [1..1000000]).join()
			expect(testReplace(@inFile, 2, data, @checksums)).to.be.rejectedWith(RangeError)
	describe.skip 'with buffer input', ->
		it 'replaces successfully', ->
			data = new Buffer("test string")	
			testReplace(@inFile, 2, data, @checksums)
		it 'does not allow buffers larger than the partition', ->
			data = new Buffer(1000000)
			expect(testReplace(@inFile, 2, data, @checksums)).to.be.rejectedWith(RangeError)
	describe 'with stream input', ->
		it 'replaces successfully', ->
			data = fs.createReadStream("./package.json")
			testReplace(@inFile, 2, data, @checksums)	
		it 'emits error event for streams larger than the partition', ->
			return
			data = fs.createReadStream("/dev/zero", { start: 0, end: 1000000 })
			testReplace(@inFile, 2, data, @checksums)
			
