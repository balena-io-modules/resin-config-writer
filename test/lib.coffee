Promise = require 'bluebird'
tmp = Promise.promisifyAll(require('tmp'))
streamToPromise = require 'stream-to-promise'
fs = require 'fs'
child_process = Promise.promisifyAll(require('child_process'))
{ expect } = require 'chai'

writer = require '..'

streamToFile = (srcStream, destPath) ->
	streamToPromise(srcStream.pipe(fs.createWriteStream(destPath)))

describe 'replacePartition', ->
	before ->
		@inFile = "./test/data/test.img"
		# checksums will be used to check that other partitions are not altered
		@checksums = [ fs.readFileSync("./test/data/test.1.sha256").toString().trim(), fs.readFileSync("./test/data/test.2.sha256").toString().trim() ]
		@config = JSON.stringify({ foo: "bar", color: "red" })

		Promise.all( [
			tmp.fileAsync(),
			child_process.execAsync("losetup -f")
			writer.replacePartition(@inFile, 2, @config)
		] ).spread ( [ tmpPath ], [ loopdev ], stream ) =>
			@outFile = tmpPath
			@outDisk = loopdev.toString().trim()
			@outPartition = "#{@outDisk}p3"
			streamToFile(stream, @outFile)
		.then =>
			cmd = "losetup #{@outDisk} #{@outFile} && partprobe #{@outDisk}"
			child_process.execAsync(cmd)
		.catch (e) ->
			console.error("Error: #{e.message}")
			console.error("Make sure you run tests with sudo")
			process.exit(1)

	after ->
		Promise.all( [
			fs.unlinkAsync(@outFile),
			child_process.execAsync("losetup -d #{@outDisk}")
		] )

	it 'preserves disk size', ->
		inSize = fs.statSync(@inFile).size
		outSize = fs.statSync(@outFile).size
		expect(outSize).to.equal(inSize)

	it 'writes configuration into partition', ->
		fs.readFileAsync(@outPartition)
		.then (data) =>
			expect(data.toString().replace(/\0/g, '')).to.equal(@config)

	it 'does not alter other partitions', ->
		Promise.all( [
			child_process.execAsync("sha256sum -b #{@outDisk}p1"),
			child_process.execAsync("sha256sum -b #{@outDisk}p2")
		] ).spread (p1sum, p2sum) =>
			expect(p1sum.toString().slice(0,64)).to.equal(@checksums[0])
			expect(p2sum.toString().slice(0,64)).to.equal(@checksums[1])
