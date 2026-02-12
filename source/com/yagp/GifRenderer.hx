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
import com.yagp.structs.GifFrame;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import haxe.ds.IntMap;

typedef GifMap =
{
	var data:BitmapData;
	var width:Int;
	var height:Int;
	var frames:Array<Int>;
}

class GifRenderer
{
	private static var rect = new Rectangle();
	private static var point = new Point();

	private var _gif:Gif;
	private var _canvas:BitmapData;
	private var _restorer:BitmapData;
	private var _prevFrame = -1;
	private var _cached:IntMap<BitmapData>;
	private var _allCached = false;

	public function new(gif:Gif)
	{
		_gif = gif;
		_canvas = new BitmapData(gif.width, gif.height, true, 0);
		_cached = new IntMap<BitmapData>();
	}

	public static function createMap(gif:Gif, vertical = false):GifMap
	{
		var renderer = new GifRenderer(gif);
		renderer.cacheAllFrames();

		var fcount = gif.frames.length;
		var sw = gif.width;
		var sh = gif.height;
		var cols = vertical ? 1 : fcount;
		var rows = vertical ? fcount : 1;

		var sheet = new BitmapData(sw * cols, sh * rows, true, 0);
		sheet.lock();
		var dx = vertical ? 0 : sw;
		var dy = vertical ? sh : 0;
		for (i in 0...fcount)
		{
			var frame = renderer._cached.get(i);
			if (frame != null)
			{
				point.x = dx * i;
				point.y = dy * i;
				sheet.copyPixels(frame, frame.rect, point);
			}
		}
		sheet.unlock();

		var delays = [];
		for (f in gif.frames) delays.push(f.delay);
		renderer.dispose();
		return { data: sheet, width: sw, height: sh, frames: delays };
	}

	public function setTarget(target:BitmapData):Void
	{
		_canvas.dispose();
		_canvas = target;
	}

	public function render(frame:Int, offsetX:Int, offsetY:Int):Void
	{
		if (_gif == null || frame >= _gif.frames.length || frame < 0) return;
		ensureFrameCached(frame);
		if (_cached.exists(frame))
		{
			point.x = offsetX;
			point.y = offsetY;
			_canvas.copyPixels(_cached.get(frame), _cached.get(frame).rect, point);
			_prevFrame = frame;
		}
	}

	public function getCachedFrame(frame:Int):BitmapData
	{
		if (frame < 0 || frame >= _gif.frames.length) return null;
		ensureFrameCached(frame);
		return _cached.get(frame);
	}

	public function cacheAllFrames():Void
	{
		if (_allCached) return;
		var oldTarget = _canvas;
		var oldPrev = _prevFrame;
		_canvas = new BitmapData(_gif.width, _gif.height, true, 0);
		_prevFrame = -1;
		_canvas.lock();
		for (i in 0..._gif.frames.length)
		{
			if (_cached.exists(i)) continue;
			renderSingleFrame(i);
			var cached = new BitmapData(_gif.width, _gif.height, true, 0);
			cached.copyPixels(_canvas, _canvas.rect, new Point());
			_cached.set(i, cached);
			if (i < _gif.frames.length - 1) applyDisposalMethod(i);
		}
		_canvas.unlock();
		_canvas.dispose();
		_canvas = oldTarget;
		_prevFrame = oldPrev;
		_allCached = true;
	}

	private function ensureFrameCached(frame:Int):Void
	{
		if (_cached.exists(frame)) return;
		var start = 0;
		for (i in 0...frame)
			if (_cached.exists(i)) start = i + 1;
		if (start > 0)
		{
			var last = _cached.get(start - 1);
			_canvas.copyPixels(last, last.rect, new Point());
			_prevFrame = start - 1;
		}
		else
		{
			_canvas.fillRect(_canvas.rect, 0);
			_prevFrame = -1;
		}
		for (i in start...frame + 1)
		{
			renderSingleFrame(i);
			var cached = new BitmapData(_gif.width, _gif.height, true, 0);
			cached.copyPixels(_canvas, _canvas.rect, new Point());
			_cached.set(i, cached);
			if (i < _gif.frames.length - 1) applyDisposalMethod(i);
		}
	}

	private inline function renderSingleFrame(idx:Int):Void
	{
		var f = _gif.frames[idx];
		if (f.disposalMethod == DisposalMethod.RENDER_PREVIOUS)
		{
			if (_restorer != null) _restorer.dispose();
			rect.setTo(f.x, f.y, f.width, f.height);
			_restorer = new BitmapData(f.width, f.height, true, 0);
			_restorer.copyPixels(_canvas, rect, new Point());
		}
		point.setTo(f.x, f.y);
		_canvas.copyPixels(f.data, f.data.rect, point, null, null, true);
		_prevFrame = idx;
	}

	private inline function applyDisposalMethod(idx:Int):Void
	{
		var f = _gif.frames[idx];
		switch (f.disposalMethod)
		{
			case DisposalMethod.FILL_BACKGROUND:
				rect.setTo(f.x, f.y, f.width, f.height);
				_canvas.fillRect(rect, 0x00000000);
			case DisposalMethod.RENDER_PREVIOUS:
				if (_restorer != null)
				{
					point.setTo(f.x, f.y);
					_canvas.copyPixels(_restorer, _restorer.rect, point);
					_restorer.dispose();
					_restorer = null;
				}
			default:
		}
	}

	public function dispose():Void
	{
		if (_restorer != null) { _restorer.dispose(); _restorer = null; }
		if (_canvas != null) { _canvas.dispose(); _canvas = null; }
		for (bd in _cached) bd.dispose();
		_cached.clear();
		_gif = null;
	}
}