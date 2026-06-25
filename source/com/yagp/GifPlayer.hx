/*
 * This work is licensed under MIT license.
 * 
 * Copyright (C) 2014 Pavel "Yanrishatum" Alexandrov
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this
 * software and associated documentation files (the "Software"), to deal in the Software
 * without restriction, including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software, and to permit
 * persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or
 * substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
 * PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
 * FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package com.yagp;

import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;

class GifPlayer
{
	private static var point:Point = new Point();

	public var data(default, null):BitmapData;

	public var playing:Bool = true;
	public var loopEndHandler:Void->Void;
	public var animationEndHandler:Void->Void;
	public var minFrameDelay:Float = 10.0;
	public var maxFrameAdvance:Int = 4;

	public var gif(default, set):Null<Gif>;
	public var frame(get, set):Int;
	public var framesCount(get, never):Int;
	public var speed(default, set):Float = 1.0;

	private var _map:GifRenderer.GifMap;
	private var _frames:Array<Int>;
	private var _currFrame:Int = 0;
	private var _loops:Int = 0;
	private var _maxLoops:Int = 0;
	private var _time:Float = 0;

	private var _sheet:BitmapData;
	private var _rects:Array<Rectangle>;

	public function new(gif:Null<Gif> = null)
	{
		this.gif = gif;
	}

	private function set_gif(value:Null<Gif>):Null<Gif>
	{
		if (value == gif) return value;

		cleanup();
		gif = value;

		if (gif == null) return null;

		_map = GifRenderer.createMap(gif);
		_frames = _map.delays;

		_currFrame = 0;
		_loops = 0;
		_maxLoops = gif.loops;
		_time = 0;
		playing = true;

		data = new BitmapData(_map.width, _map.height, true, 0);

		buildRenderer();
		renderCurrentFrame();

		return gif;
	}

	private function buildRenderer():Void
	{
		_sheet = _map.data;
		_rects = [];

		final cols = Math.ceil(Math.sqrt(_frames.length));

		for (i in 0..._frames.length)
		{
			final curCol = i % cols;
			final curRow = Math.floor(i / cols);

			_rects[i] = new Rectangle(
				curCol * _map.width, 
				curRow * _map.height, 
				_map.width, 
				_map.height
			);
		}
	}

	private inline function get_framesCount():Int
		return _frames != null ? _frames.length : 0;

	private inline function get_frame():Int
		return _currFrame;

	private function set_frame(value:Int):Int
	{
		if (gif == null || _frames == null || _frames.length == 0) return 0;

		if (value < 0) value = 0;
		else if (value >= _frames.length) value = _frames.length - 1;

		_currFrame = value;
		_time = 0;

		renderCurrentFrame();
		return _currFrame;
	}

	private function set_speed(value:Float):Float
	{
		speed = value <= 0 ? 0.0001 : value;
		return speed;
	}

	public function update(elapsed:Float):Void
	{
		if (!playing || gif == null || _frames == null || _frames.length == 0) return;

		_time += elapsed * 1000.0;
		var advanced = 0;

		while (_time >= Math.max(minFrameDelay, _frames[_currFrame] / speed))
		{
			var delay = Math.max(minFrameDelay, _frames[_currFrame] / speed);
			_time -= delay;
			nextFrame();
			
			advanced++;
			if (advanced >= maxFrameAdvance)
			{
				_time = 0;
				break;
			}
		}
	}

	private function nextFrame():Void
	{
		_currFrame++;

		if (_currFrame >= _frames.length)
		{
			if (loopEndHandler != null) loopEndHandler();

			if (_maxLoops != 0)
			{
				_loops++;
				if (_loops >= _maxLoops)
				{
					_currFrame = _frames.length - 1;
					playing = false;

					if (animationEndHandler != null) animationEndHandler();

					renderCurrentFrame();
					return;
				}
			}
			_currFrame = 0;
		}

		renderCurrentFrame();
	}

	private inline function renderCurrentFrame():Void
	{
		if (_sheet == null || data == null || _rects == null) return;
		data.copyPixels(_sheet, _rects[_currFrame], point, null, null, false);
	}

	public function reset(play:Bool = false):Void
	{
		if (gif == null) return;

		_currFrame = 0;
		_loops = 0;
		_time = 0;

		if (play) playing = true;

		renderCurrentFrame();
	}

	public function getBitmapFrame(index:Int):BitmapData
	{
		if (_sheet == null || _rects == null) return null;
		if (index < 0 || index >= _rects.length) return null;

		var bitmap = new BitmapData(_map.width, _map.height, true, 0);
		bitmap.copyPixels(_sheet, _rects[index], point, null, null, false);
		return bitmap;
	}

	private function cleanup():Void
	{
		if (data != null)
		{
			data.dispose();
			data = null;
		}

		if (_sheet != null)
		{
			_sheet.dispose();
			_sheet = null;
		}

		_map = null;
		_frames = null;
		_rects = null;
	}

	public function dispose(disposeGif:Bool = false):Void
	{
		if (disposeGif && gif != null) 
			gif.dispose();

		gif = null;
		cleanup();

		loopEndHandler = null;
		animationEndHandler = null;
	}
}