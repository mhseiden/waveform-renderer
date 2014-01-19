###

	A waveform object provides an API for rendering a data array or MP3 url onto a canvas. The object is initialized 
	with a <div> element that will contain the canvas on which the waveform will be rendered. Once specified, the 
	object will also provide hooks for changing the zoom level and offset of the visible portion - the idea is that a 
	user could use this as a foundational element for an audio editor or instrument, such as a sampler.

###
class Waveform

	constructor: (@_container)->
		# Create the canvas container
		canvasContainer = document.createElement "div"
		canvasContainer.setAttribute("id", "canvas-container")
		@_container.appendChild canvasContainer

		# Create the canvas
		@_canvas = document.createElement("canvas")
		@_canvas.width = @_container.clientWidth - @CONTROL_SIZE - 1 # border
		@_canvas.height = @_container.clientHeight - @CONTROL_SIZE
		canvasContainer.appendChild @_canvas

		# Create the controls
		@_container.appendChild @_controls()

		# Center the container vertically
		@_container.style["margin-top"] = "#{document.body.clientHeight / 2}px"
		@_container.style["top"] = "-#{@_container.clientHeight / 2}px"

	_data: []			# Data Buffer that holds the waveform
	_zoom: 1.0		# The fraction of the entire data array that is visible (0.0 < zoom <= 1.0)
	_start: 0.0		# The left offset from array idx 0 (0.0 <= left < 1.0)
	_image: null

	X_SCALE: 0.05
	Y_SCALE: 0.8
	DOWNSAMPLE_TARGET: 100000
	CONTROL_SIZE: 20

	_controls: ->
		controls = document.createElement "div"
		controls.setAttribute("id", "control-container")

		for [id, text] in [["ctrl-in", "+"], ["ctrl-out", "&mdash;"], ["ctrl-left", "&larr;"], ["ctrl-right", "&rarr;"]]
			box = document.createElement "div"
			box.setAttribute("id", id)
			box.setAttribute("class", "ctrl-box")
			box.innerHTML = text
			controls.appendChild box
		@_controls = controls

	_audio: new webkitAudioContext()

	waveformFromMP3URL: (url, cb = (->)) ->
		xhr = new XMLHttpRequest()
		xhr.responseType = "arraybuffer"
		xhr.open("GET", url)

		xhr.addEventListener "readystatechange", =>
			if(4 == xhr.readyState)
				@_audio.decodeAudioData xhr.response, (aud) =>
					downsample = Math.ceil aud.getChannelData(0).length / @DOWNSAMPLE_TARGET
				 `// Writing this in javascript since coffeescript makes it annoying
				  var max = Number.MIN_VALUE; // for normalization
					var buf = new Float32Array(aud.length / downsample)
					for(var bin = 0, len1 = buf.length; bin < len1; ++bin) {
						var avg = 0.0;
						for(var chan = 0, len3 = aud.numberOfChannels; chan < len3; ++chan) {
							var chanData = aud.getChannelData(chan);
							for(var idx = bin * downsample, len2 = idx + downsample; idx < len2; ++idx) {
								avg += chanData[idx];
							}
						}
						avg /= (aud.numberOfChannels * downsample);
						buf[bin] = avg;
						max = Math.max(avg, max);
					}

					for(bin = 0; bin < len1; ++bin) {
						buf[bin] = buf[bin] / max;
					}

					_this.waveformFromArray(buf, cb)`
					return

		xhr.send()

	waveformFromArray: (buf, cb = (->)) ->
		# Reset the internal values
		@_zoom = 1
		@_start = 0.0

		# Make the assignment
		@_data = buf

		# Render the waveform in the selected bar
		@_initSelected()

		# Make the render call with the high res iterator
		@_render cb

	zoom: (zoom) ->
		if zoom != @_zoom
			@_zoom = zoom
			@_render()

	zoomIn: ->
		zoom = Math.max(10 / @_length(), @_zoom * @Y_SCALE)
		if @_zoom != zoom
			@_zoom = zoom
			@_render()

	zoomOut: ->
		zoom = Math.min(1.0, @_zoom / @Y_SCALE)
		if @_zoom != zoom
			@_zoom = zoom
			@_start = @_correctStart @_start # Zooming out will change the start bounds
			@_render()

	# Compute how much to move over, given the current zoom level and X_SCALE
	_panDiff: ->
		dataLength = Math.ceil @_length() * @_zoom
		dataStart = Math.floor @_length() * @_start
		dataEnd = Math.min (@_length() - 1), dataStart + dataLength
		@X_SCALE * (dataEnd - dataStart) / @_length()
	
	# Check if there is any overflow and update the new start accordingly
	_correctStart: (start) ->
		length = @_length() * @_zoom
		start = @_length() * start
		overflow = start + (length - @_length())

		if(overflow > 0.0)
			((@_length() - length) / @_length())
		else
			start / @_length()

	pan: (val) ->
		start = Math.max(0.0, Math.min(1.0 - @_panDiff(), @_correctStart val))
		if start != @_start
			@_start = start
			@_render()

	panRight: ->
		start = Math.min(1.0 - @_panDiff(), @_correctStart @_start + @_panDiff())
		if start != @_start
			@_start = start
			@_render()

	panLeft: ->
		start = Math.max(0.0, @_correctStart @_start - @_panDiff())
		if start != @_start
			@_start = start
			@_render()

	_render: (cb = (->), iteratorName = "renderIterator") ->
		# Not used in the actual rendering - only needed for computation 
		_dataLength = Math.ceil @_length() * @_zoom

		# The rendering bounds for the data array
		dataStart = Math.floor @_length() * @_start
		dataEnd = Math.min (@_length() - 1), dataStart + _dataLength

		# Select a rendering iterator
		it = this["_" + iteratorName](dataStart, dataEnd)
		
		it.open() # Do initial setup
		it.next() while it.hasNext()
		it.close() # Do final cleanup

		# Render the controls
		@_renderSelected()

		# We're all done, so notify the troops
		cb()

	
	_initSelected: ->
		# Create the selected canvas and append it
		selected = document.getElementById("selected-container")
		canvas = document.createElement "canvas"
		selected.appendChild canvas

		# set the width and height and render
		canvas.width = selected.clientWidth
		canvas.height = selected.clientHeight
		swap = @_canvas
		@_canvas = canvas
		@_render()
		@_canvas = swap

	_renderSelected: ->
		selected = document.getElementById("selected-bar")
		width = @_zoom * 100
		offset = (@_width() + @CONTROL_SIZE + 1) * @_start
		selected.style["width"] = "#{width}%"
		selected.style["left"] = "#{offset}px"

	# Render using the input data array
	_renderIteratorHighRes: (dataStart, dataEnd) ->
		console.log "Zoom #{@_zoom} and Start #{@_start}"
		
		# Create a data subarray for the cause (the +1 is to ensure we have data to draw to the end of the canvas)
		data = @_data.subarray(dataStart, dataEnd + 1)
		length = data.length

		# Compute the step size and create helper fns
		stepSize = @_width() / (dataEnd - dataStart)
		height = @_height()

		xCoord = (idx) => stepSize * idx
		xNext = (idx) => xCoord(idx + 1)

		yCoord = (idx) => (((0.95 * data[idx]) + 1.0) / 2.0) * height
		yNext = (idx) => yCoord(idx + 1)

		# Logging is good for the soul!
		console.log "Length #{length} and Step #{stepSize}"

		# Rendering internals
		index = 0
		context = @_canvas.getContext("2d")
		context.fillStyle = "#FFF"
		context.fillRect(0, 0, @_width(), @_height())

		open: =>
			context.beginPath()
			context.moveTo xCoord(index), yCoord(index)
		close: ->
			# Ensure that we go to the end of the canvas
			@next() while yCoord(index) < _this._width() # `_this` is ensured by the `=>` elsewhere
			context.stroke()
		hasNext: =>
			index < (length - 1)
		next: =>
			# context.lineTo xCoord(index), yCoord(index)
			
			# From: http://stackoverflow.com/questions/7054272
			xc = (xCoord(index) + xNext(index)) / 2
			yc = (yCoord(index) + yCoord(index)) / 2
			context.quadraticCurveTo(xCoord(index), yCoord(index), xc, yc)

			++index

	# Make it easy to switch which rendering iterator is used
	_renderIterator: @::_renderIteratorHighRes
			
	_length: -> @_data.length
	_width: -> @_canvas.width
	_height: -> @_canvas.height
