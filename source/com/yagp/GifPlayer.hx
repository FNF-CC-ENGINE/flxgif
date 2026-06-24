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
import openfl.display.Tile;
import openfl.display.Tilemap;
import openfl.display.Tileset;
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

	public var gif(get, set):Null<Gif>;
	public var frame(get, set):Int;
	public var framesCount(get, never):Int;
	public var speed(get, set):Float;
	public var targetFPS(default, set):Float = 30.0;
	public var useHardware(default, set):Bool = true;

	public var tilemap(default, null):Tilemap;

	private var _gif:Null<Gif>;
	private var _map:GifRenderer.GifMap;
	private var _frames:Array<Int>;
	private var _currFrame:Int = 0;
	private var _loops:Int = 0;
	private var _maxLoops:Int = 0;
	private var _time:Float = 0;
	private var _speed:Float = 1.0;

	private var _tileset:Tileset;
	private var _tile:Tile;
	private var _sheet:BitmapData;
	private var _rects:Array<Rectangle>;
	private var _hardwareAvailable:Bool;

	public function new(gif:Null<Gif> = null)
	{
		_hardwareAvailable = #if (openfl >= "7.0.0") true #else false #end;
		this.gif = gif;
	}

	private inline function get_gif():Null<Gif>
		return _gif;

	private function set_gif(value:Null<Gif>):Null<Gif>
	{
		if (value == _gif) return value;

		cleanup();

		_gif = value;

		if (_gif == null)
			return null;

		_map = GifRenderer.createMap(_gif, true);
		_frames = _map.delays;

		_currFrame = 0;
		_loops = 0;
		_maxLoops = _gif.loops;
		_time = 0;
		playing = true;

		data = new BitmapData(_map.width, _map.height, true, 0);

		buildRenderer();
		renderCurrentFrame();

		return _gif;
	}

	private function buildRenderer():Void
	{
		_sheet = _map.data;
		_rects = [];

		for (i in 0..._frames.length)
			_rects[i] = new Rectangle(0, i * _map.height, _map.width, _map.height);

		if (useHardware)
			buildTilemap();
	}

	private function buildTilemap():Void
	{
		#if (openfl >= "7.0.0")
		if (_sheet == null) return;

		_tileset = new Tileset(_sheet);

		for (rect in _rects)
			_tileset.addRect(rect);

		tilemap = new Tilemap(_map.width, _map.height, _tileset);

		_tile = new Tile(0);
		tilemap.addTile(_tile);
		#end
	}

	private inline function get_framesCount():Int
		return _frames != null ? _frames.length : 0;

	private inline function get_frame():Int
		return _currFrame;

	private function set_frame(value:Int):Int
	{
		if (_gif == null || _frames == null || _frames.length == 0)
			return 0;

		if (value < 0)
			value = 0;
		else if (value >= _frames.length)
			value = _frames.length - 1;

		_currFrame = value;
		_time = 0;

		renderCurrentFrame();

		return _currFrame;
	}

	private inline function get_speed():Float
		return _speed;

	private function set_speed(value:Float):Float
	{
		_speed = value <= 0 ? 0.0001 : value;
		return _speed;
	}

	private function set_targetFPS(value:Float):Float
	{
		targetFPS = value <= 0 ? 1 : value;
		return targetFPS;
	}

	private function set_useHardware(value:Bool):Bool
	{
		useHardware = value && _hardwareAvailable;

		if (_gif != null)
		{
			destroyHardware();

			if (useHardware)
				buildTilemap();

			renderCurrentFrame();
		}

		return useHardware;
	}

	public function update(elapsed:Float):Void
	{
		if (!playing || _gif == null || _frames == null || _frames.length == 0)
			return;

		_time += elapsed * 1000.0;

		var advanced = 0;
		var delay = Math.max(minFrameDelay, _frames[_currFrame] / _speed);

		while (_time >= delay && advanced < maxFrameAdvance)
		{
			_time -= delay;
			nextFrame();
			advanced++;

			if (!playing)
				break;

			delay = Math.max(minFrameDelay, _frames[_currFrame] / _speed);
		}

		if (advanced >= maxFrameAdvance)
			_time = 0;
	}

	private function nextFrame():Void
	{
		_currFrame++;

		if (_currFrame >= _frames.length)
		{
			if (loopEndHandler != null)
				loopEndHandler();

			if (_maxLoops != 0)
			{
				_loops++;

				if (_loops >= _maxLoops)
				{
					_currFrame = _frames.length - 1;
					playing = false;

					if (animationEndHandler != null)
						animationEndHandler();

					renderCurrentFrame();
					return;
				}
			}

			_currFrame = 0;
		}

		renderCurrentFrame();
	}

	private function renderCurrentFrame():Void
	{
		if (_sheet == null || data == null || _rects == null)
			return;

		if (useHardware && tilemap != null && _tile != null)
		{
			#if (openfl >= "7.0.0")
			_tile.id = _currFrame;
			#end
		}

		data.fillRect(data.rect, 0);
		point.setTo(0, 0);
		data.copyPixels(_sheet, _rects[_currFrame], point, null, null, true);
	}

	public function reset(play:Bool = false):Void
	{
		if (_gif == null) return;

		_currFrame = 0;
		_loops = 0;
		_time = 0;

		if (play)
			playing = true;

		renderCurrentFrame();
	}

	public function getBitmapFrame(index:Int):BitmapData
	{
		if (_sheet == null || _rects == null) return null;
		if (index < 0 || index >= _rects.length) return null;

		var bitmap = new BitmapData(_map.width, _map.height, true, 0);
		point.setTo(0, 0);
		bitmap.copyPixels(_sheet, _rects[index], point);
		return bitmap;
	}

	private function destroyHardware():Void
	{
		tilemap = null;
		_tile = null;
		_tileset = null;
	}

	private function cleanup():Void
	{
		destroyHardware();

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
		if (disposeGif && _gif != null)
			_gif.dispose();

		_gif = null;
		cleanup();

		loopEndHandler = null;
		animationEndHandler = null;
	}
}