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

import com.yagp.structs.DisposalMethod;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import haxe.ds.IntMap;

typedef GifMap =
{
	var data:BitmapData;
	var width:Int;
	var height:Int;
	var delays:Array<Int>;
}

class GifRenderer
{
	private static var rect:Rectangle = new Rectangle();
	private static var point:Point = new Point();

	private var _gif:Gif;
	private var _canvas:BitmapData;
	private var _restore:BitmapData;
	private var _cached:IntMap<BitmapData>;
	private var _allCached:Bool = false;

	public function new(gif:Gif)
	{
		_gif = gif;
		_canvas = new BitmapData(gif.width, gif.height, true, 0);
		_cached = new IntMap<BitmapData>();
	}

	public static function createMap(gif:Gif):GifMap
	{
		var renderer = new GifRenderer(gif);
		renderer.cacheAllFrames();

		var count = gif.frames.length;
		var frameWidth = gif.width;
		var frameHeight = gif.height;

		var cols = Math.ceil(Math.sqrt(count));
		var rows = Math.ceil(count / cols);

		var sheet = new BitmapData(frameWidth * cols, frameHeight * rows, true, 0);
		sheet.lock();

		for (i in 0...count)
		{
			var frame = renderer._cached.get(i);
			if (frame == null) continue;

			var curCol = i % cols;
			var curRow = Math.floor(i / cols);

			point.setTo(frameWidth * curCol, frameHeight * curRow);
			sheet.copyPixels(frame, frame.rect, point);
		}

		sheet.unlock();

		var delays:Array<Int> = [];
		for (frame in gif.frames)
			delays.push(frame.delay);

		renderer.dispose();

		return {
			data: sheet,
			width: frameWidth,
			height: frameHeight,
			delays: delays
		};
	}

	public function render(frame:Int, target:BitmapData, offsetX:Int = 0, offsetY:Int = 0, clearTarget:Bool = false):Void
	{
		if (_gif == null || target == null) return;
		if (frame < 0 || frame >= _gif.frames.length) return;

		var cached = getCachedFrame(frame);
		if (cached == null) return;

		if (clearTarget)
			target.fillRect(target.rect, 0);

		point.setTo(offsetX, offsetY);
		target.copyPixels(cached, cached.rect, point, null, null, true);
	}

	public function getCachedFrame(frame:Int):BitmapData
	{
		if (_gif == null) return null;
		if (frame < 0 || frame >= _gif.frames.length) return null;

		ensureFrameCached(frame);
		return _cached.get(frame);
	}

	public function cacheAllFrames():Void
	{
		if (_gif == null || _allCached) return;

		_canvas.lock();
		_canvas.fillRect(_canvas.rect, 0);

		for (i in 0..._gif.frames.length)
		{
			if (!_cached.exists(i))
			{
				renderSingleFrame(i);
				cacheCanvas(i);
			}

			if (i < _gif.frames.length - 1)
				applyDisposalMethod(i);
		}

		_canvas.unlock();
		_allCached = true;
	}

	private function ensureFrameCached(frame:Int):Void
	{
		if (_cached.exists(frame)) return;

		var start = 0;

		for (i in 0...frame)
		{
			if (_cached.exists(i))
				start = i + 1;
		}

		if (start > 0)
		{
			final previous = _cached.get(start - 1);
			_canvas.fillRect(_canvas.rect, 0);

			point.setTo(0, 0);
			_canvas.copyPixels(previous, previous.rect, point);
		}
		else
		{
			_canvas.fillRect(_canvas.rect, 0);
		}

		for (i in start...frame + 1)
		{
			renderSingleFrame(i);
			cacheCanvas(i);

			if (i < _gif.frames.length - 1)
				applyDisposalMethod(i);
		}
	}

	private inline function cacheCanvas(frame:Int):Void
	{
		var cached = new BitmapData(_gif.width, _gif.height, true, 0);
		point.setTo(0, 0);
		cached.copyPixels(_canvas, _canvas.rect, point);
		_cached.set(frame, cached);
	}

	private function renderSingleFrame(index:Int):Void
	{
		var frame = _gif.frames[index];

		if (frame.disposalMethod == DisposalMethod.RENDER_PREVIOUS)
		{
			if (_restore != null)
				_restore.dispose();

			rect.setTo(frame.x, frame.y, frame.width, frame.height);
			_restore = new BitmapData(frame.width, frame.height, true, 0);
			point.setTo(0, 0);
			_restore.copyPixels(_canvas, rect, point);
		}

		point.setTo(frame.x, frame.y);
		_canvas.copyPixels(frame.data, frame.data.rect, point, null, null, true);
	}

	private function applyDisposalMethod(index:Int):Void
	{
		var frame = _gif.frames[index];

		switch (frame.disposalMethod)
		{
			case DisposalMethod.FILL_BACKGROUND:
				rect.setTo(frame.x, frame.y, frame.width, frame.height);
				_canvas.fillRect(rect, 0);

			case DisposalMethod.RENDER_PREVIOUS:
				if (_restore != null)
				{
					point.setTo(frame.x, frame.y);
					_canvas.copyPixels(_restore, _restore.rect, point);
					_restore.dispose();
					_restore = null;
				}

			default:
		}
	}

	public function dispose():Void
	{
		if (_restore != null)
		{
			_restore.dispose();
			_restore = null;
		}

		if (_canvas != null)
		{
			_canvas.dispose();
			_canvas = null;
		}

		if (_cached != null)
		{
			for (bitmap in _cached)
				bitmap.dispose();

			_cached.clear();
			_cached = null;
		}

		_gif = null;
	}
}