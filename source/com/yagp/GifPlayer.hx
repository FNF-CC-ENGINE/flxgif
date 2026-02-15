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
import openfl.display.Tile;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import haxe.ds.IntMap;

class GifPlayer
{
	private static var rect = new Rectangle();
	private static var point = new Point();

	public var data(default, null):BitmapData;

	public var playing = true;
	public var animationEndHandler:Void->Void;
	public var loopEndHandler:Void->Void;
	public var performanceMode = false;
	public var skipFrames = false;
	public var maxCachedFrames = 20;

	public var gif(get, set):Null<Gif>;
	public var frame(get, set):Int;
	public var framesCount(get, never):Int;
	public var speed(get, set):Float;
	public var targetFPS(default, set):Float = 30.0;
	public var tilemap(default, null):Tilemap;
	public var useHardware(default, set):Bool = true;

	private var _gif:Null<Gif>;
	private var _frames:Array<GifFrame>;
	private var _currFrame = 0;
	private var _currGifFrame:GifFrame;
	private var _prevData:BitmapData;
	private var _loops = 0;
	private var _maxLoops = 0;
	private var _t = 0.0;
	private var _speed:Float = 1.0;
	private var _cachedFrames:IntMap<BitmapData>;
	private var _cacheDirty = true;
	private var _frameDelays:Array<Float>;
	private var _lastUpdate = 0.0;
	private var _frameBudget = 0.0;
	private var _perfTimer = 0.0;
	private var _rendered = 0;

	private var _tileset:Tileset;
	private var _hardwareTile:Tile;
	private var _hardwareAvailable:Bool;
	private var _spritesheet:BitmapData;
	private var _spriteRects:Array<Rectangle>;

	public function new(gif:Null<Gif>)
	{
		_cachedFrames = new IntMap<BitmapData>();
		_hardwareAvailable = #if (openfl >= "7.0.0") true #else false #end;
		_frameBudget = 1000.0 / targetFPS;
		this.gif = gif;
	}

	private function set_useHardware(v:Bool):Bool
	{
		useHardware = v && _hardwareAvailable;
		if (_gif != null) rebuildRenderer();
		return useHardware;
	}

	private function set_targetFPS(v:Float):Float
	{
		targetFPS = v;
		_frameBudget = 1000.0 / targetFPS;
		return v;
	}

	private inline function get_gif():Null<Gif> return _gif;
	private function set_gif(v:Null<Gif>):Null<Gif>
	{
		if (v == _gif) return v;
		cleanup();
		if (v == null) return _gif = null;
		_gif = v;
		_frames = v.frames;
		_currFrame = 0;
		_t = 0;
		_loops = 0;
		_maxLoops = _gif.loops;
		playing = true;
		_cacheDirty = true;
		_lastUpdate = 0;
		_perfTimer = 0;
		_rendered = 0;
		precomputeDelays();

		if (data == null || data.width != v.width || data.height != v.height)
		{
			if (data != null) data.dispose();
			data = new BitmapData(v.width, v.height, true, 0);
		}
		else data.fillRect(data.rect, 0);

		rebuildRenderer();
		return v;
	}

	private function rebuildRenderer():Void
	{
		if (_gif == null) return;
		if (useHardware)
			buildTilemap();
		else
			buildSpritesheet();

		_currGifFrame = _frames[0];
		renderCurrentFrame();
	}

	private function precomputeDelays():Void
	{
		if (_frames == null) return;
		_frameDelays = [];
		for (f in _frames) _frameDelays.push(f.delay);
	}

	private function cleanup():Void
	{
		if (_prevData != null) { _prevData.dispose(); _prevData = null; }
		clearCache();
		_frameDelays = null;
		if (_tileset != null) { _tileset.bitmapData.dispose(); _tileset = null; }
		tilemap = null;
		if (_spritesheet != null) { _spritesheet.dispose(); _spritesheet = null; }
		_spriteRects = null;
	}

	private function clearCache():Void
	{
		for (bd in _cachedFrames) bd.dispose();
		_cachedFrames.clear();
	}

	private function buildTilemap():Void
	{
		#if (openfl >= "7.0.0")
		var map = GifRenderer.createMap(_gif, true);
		_tileset = new Tileset(map.data);
		for (i in 0..._frames.length)
			_tileset.addRect(new Rectangle(0, i * _gif.height, _gif.width, _gif.height));
		tilemap = new Tilemap(_gif.width, _gif.height, _tileset);
		
		var tile = new Tile(0);
		tilemap.addTile(tile);
		_hardwareTile = tile;
		
		if (data != null) data.dispose();
		data = new BitmapData(_gif.width, _gif.height, true, 0);
		updateDataFromTilemap();
		#end
	}

	private inline function updateDataFromTilemap():Void
	{
		#if (openfl >= "7.0.0")
		if (tilemap == null) return;
		data.lock();
		data.fillRect(data.rect, 0);
		data.draw(tilemap);
		data.unlock();
		#end
	}

	private function buildSpritesheet():Void
	{
		var map = GifRenderer.createMap(_gif, true);
		_spritesheet = map.data;
		_spriteRects = [];
		var h = _gif.height;
		for (i in 0..._frames.length)
			_spriteRects[i] = new Rectangle(0, i * h, _gif.width, h);
	}

	private inline function get_framesCount():Int
		return _frames != null ? _frames.length : 0;

	private inline function get_frame():Int return _currFrame;
	private function set_frame(v:Int):Int
	{
		if (_gif == null) return v;
		v = Std.int(Math.max(0, Math.min(v, _frames.length - 1)));
		if (_currFrame == v) return v;
		_t = 0;
		
		if (useHardware && tilemap != null)
		{
			#if (openfl >= "7.0.0")
			_hardwareTile.id = v;
			updateDataFromTilemap();
			#end
		}
		else
		{
			renderFrame(v);
		}
		
		_currFrame = v;
		_currGifFrame = _frames[v];
		return _currFrame;
	}

	private inline function get_speed():Float return _speed;
	private function set_speed(v:Float):Float
	{
		_speed = v <= 0 ? 0.0001 : v;
		return _speed;
	}

	public function update(elapsed:Float):Void
	{
		if (!playing || _gif == null || _frames == null) return;
		
		_t += elapsed * 1000;
		
		advanceFrames();

		if (performanceMode)
		{
			_perfTimer += elapsed * 1000;
			if (_perfTimer >= _frameBudget)
			{
				_perfTimer -= _frameBudget;
				renderCurrentFrame();
				_rendered++;
			}
		}
		else
		{
			renderCurrentFrame();
			_rendered++;
		}
	}

	private function advanceFrames():Void
	{
		while (_t >= _currGifFrame.delay / _speed)
		{
			_t -= _currGifFrame.delay / _speed;
			renderNext();
		}
	}

	private function renderNext():Void
	{
		_currFrame++;
		if (_currFrame == _frames.length)
		{
			if (_maxLoops != 0 && ++_loops >= _maxLoops)
			{
				playing = false;
				_currFrame--;
				_t = _currGifFrame.delay / _speed;
				if (animationEndHandler != null) animationEndHandler();
				return;
			}
			_currFrame = 0;
			if (_prevData != null) { _prevData.dispose(); _prevData = null; }
		}
		else
		{
			disposeFrame(_currGifFrame);
		}

		_currGifFrame = _frames[_currFrame];
		renderFrame(_currFrame);
	}

	private function renderCurrentFrame():Void
	{
		if (useHardware && tilemap != null)
		{
			#if (openfl >= "7.0.0")
			_hardwareTile.id = _currFrame;
			updateDataFromTilemap();
			#end
		}
		else
		{
			renderFrame(_currFrame);
		}
	}

	private function renderFrame(idx:Int):Void
	{
		var frame = _frames[idx];
		
		if (frame.disposalMethod == DisposalMethod.RENDER_PREVIOUS)
		{
			if (_prevData != null) _prevData.dispose();
			rect.setTo(frame.x, frame.y, frame.width, frame.height);
			_prevData = new BitmapData(frame.width, frame.height, true, 0);
			_prevData.copyPixels(data, rect, point);
		}

		point.setTo(frame.x, frame.y);
		
		if (_spritesheet != null && _spriteRects != null)
		{
			rect.copyFrom(_spriteRects[idx]);
			data.copyPixels(_spritesheet, rect, point, null, null, true);
		}
		else
		{
			data.copyPixels(frame.data, frame.data.rect, point, null, null, true);
		}
	}

	private function disposeFrame(frame:GifFrame):Void
	{
		switch (frame.disposalMethod)
		{
			case DisposalMethod.FILL_BACKGROUND:
				rect.setTo(frame.x, frame.y, frame.width, frame.height);
				data.fillRect(rect, 0);
				
			case DisposalMethod.RENDER_PREVIOUS:
				if (_prevData != null)
				{
					point.setTo(frame.x, frame.y);
					data.copyPixels(_prevData, _prevData.rect, point);
					_prevData.dispose();
					_prevData = null;
				}
				
			default:
		}
	}

	public function getCachedFrame(idx:Int):BitmapData
	{
		if (_gif == null || idx < 0 || idx >= _frames.length) return null;
		if (_cachedFrames.exists(idx)) return _cachedFrames.get(idx);
		
		if (Lambda.count(_cachedFrames) >= maxCachedFrames)
		{
			var oldest:Null<Int> = null;
			for (k in _cachedFrames.keys())
			{
				oldest = k;
				break;
			}
			if (oldest != null)
			{
				_cachedFrames.get(oldest).dispose();
				_cachedFrames.remove(oldest);
			}
		}
		
		var bd = new BitmapData(_gif.width, _gif.height, true, 0);
		point.setTo(0, 0);
		
		if (_spritesheet != null)
		{
			rect.copyFrom(_spriteRects[idx]);
			bd.copyPixels(_spritesheet, rect, point);
		}
		else
		{
			var f = _frames[idx];
			bd.copyPixels(f.data, f.data.rect, point);
		}
		
		_cachedFrames.set(idx, bd);
		return bd;
	}

	public function reset(play:Bool = false):Void
	{
		if (_gif == null) return;
		_loops = 0;
		_t = 0;
		_perfTimer = 0;
		_lastUpdate = 0;
		_rendered = 0;
		if (play) playing = true;
		
		if (_prevData != null)
		{
			_prevData.dispose();
			_prevData = null;
		}
		
		_currFrame = 0;
		_currGifFrame = _frames[0];
		renderCurrentFrame();
	}

	public function dispose(disposeGif:Bool = false):Void
	{
		if (disposeGif && _gif != null) _gif.dispose();
		_gif = null;
		_currGifFrame = null;
		_frames = null;
		cleanup();
		if (data != null)
		{
			data.dispose();
			data = null;
		}
		tilemap = null;
	}

	public function getPerformanceInfo():Dynamic
	{
		return {
			cachedFrames: Lambda.count(_cachedFrames),
			totalFrames: _frames != null ? _frames.length : 0,
			renderedFrames: _rendered,
			usingCache: !_cacheDirty && Lambda.count(_cachedFrames) > 0,
			performanceMode: performanceMode,
			hardwareAccelerated: useHardware && tilemap != null
		};
	}
}