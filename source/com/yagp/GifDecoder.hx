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

import com.yagp.structs.ExtensionFactory;
import com.yagp.structs.GifBytes;
import com.yagp.structs.GifFrame;
import com.yagp.structs.GifVersion;
import com.yagp.structs.GraphicsControl;
import com.yagp.structs.GraphicsDecoder;
import com.yagp.structs.ImageDescriptor;
import com.yagp.structs.LSD;
import com.yagp.structs.NetscapeExtension;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.display.Tile;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.events.Event;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.utils.ByteArray;
import openfl.Lib;
#if (target.threaded)
import sys.thread.Thread;
#end

class GifDecoder
{
	public static function parseBytes(bytes:Bytes):Gif
	{
		var decoder = new GifDecoder(new GifBytes(bytes));
		decoder.decodeGif();
		return decoder.gif;
	}

	public static inline function parseByteArray(byteArray:ByteArray):Gif
	{
		return parseBytes(cast byteArray);
	}

	public static inline function parseText(text:String):Gif
	{
		return parseBytes(Bytes.ofString(text));
	}

	public static function parseBytesAsync(bytes:Bytes, complete:Gif->Void, error:Dynamic->Void):Bool
	{
		#if (target.threaded)
		return new GifDecoder(new GifBytes(bytes)).decodeAsync(complete, error);
		#else
		trace("Async parsing only on sys platforms.");
		return false;
		#end
	}

	public static inline function parseByteArrayAsync(byteArray:ByteArray, complete:Gif->Void, error:Dynamic->Void):Bool
	{
		#if (target.threaded)
		return parseBytesAsync(byteArray, complete, error);
		#else
		trace("Async parsing only on sys platforms.");
		return false;
		#end
	}

	public static inline function parseTextAsync(text:String, complete:Gif->Void, error:Dynamic->Void):Bool
	{
		#if (target.threaded)
		return parseBytesAsync(Bytes.ofString(text), complete, error);
		#else
		trace("Async parsing only on sys platforms.");
		return false;
		#end
	}

	public var gif(default, null):Gif;
	public var input(get, set):GifBytes;

	private var _input:GifBytes;
	private var _graphicControlExtension:GraphicsControl;
	private var _globalColorTable:Array<Int>;

	#if (target.threaded)
	private var _completeHandler:Gif->Void;
	private var _errorHandler:Dynamic->Void;
	private var _done:Bool;
	private var _error:Bool;
	private var _errorMessage:Dynamic;

	private static var _asyncDecoders:Array<GifDecoder>;
	private static var _asyncChecker:Shape;

	private static function initAsync():Void
	{
		_asyncDecoders = [];
		_asyncChecker = new Shape();
		_asyncChecker.addEventListener(Event.ENTER_FRAME, checkAsync);
		_asyncChecker.visible = false;
		Lib.current.stage.addChild(_asyncChecker);
	}

	private static function checkAsync(e:Event):Void
	{
		var i = 0;
		while (i < _asyncDecoders.length)
		{
			var d = _asyncDecoders[i];
			if (d._done)
			{
				if (d._completeHandler != null) d._completeHandler(d.gif);
				d._completeHandler = null;
				d._errorHandler = null;
				_asyncDecoders.remove(d);
				continue;
			}
			else if (d._error)
			{
				if (d._errorHandler != null) d._errorHandler(d._errorMessage);
				d._completeHandler = null;
				d._errorHandler = null;
				_asyncDecoders.remove(d);
				continue;
			}
			i++;
		}
	}
	#end

	public function new(input:GifBytes = null)
	{
		_input = input;
	}

	private inline function get_input():GifBytes return _input;
	private inline function set_input(v:GifBytes):GifBytes return _input = v;

	public function decodeAsync(complete:Gif->Void, error:Dynamic->Void):Bool
	{
		#if (target.threaded)
		if (_input == null) return false;
		if (_asyncDecoders == null) initAsync();
		_done = false;
		_error = false;
		_completeHandler = complete;
		_errorHandler = error;
		_asyncDecoders.push(this);
		Thread.create(_decodeAsync);
		return true;
		#else
		return false;
		#end
	}

	private function _decodeAsync():Void
	{
		#if (target.threaded)
		try
		{
			decodeGif();
			_done = true;
		}
		catch (e:Dynamic)
		{
			_error = true;
			_errorMessage = e;
		}
		#end
	}

	public function decodeGif():Gif
	{
		if (_input == null) return null;
		_input.position = 0;
		gif = new Gif();
		if (!readHeader()) throw "Invalid GIF header";
		var lsd = new LSD(_input);
		gif.lsd = lsd;
		if (lsd.globalColorTable)
		{
			_globalColorTable = readColorTable(lsd.globalColorTableSize);
			if (lsd.backgroundColorIndex < _globalColorTable.length)
				gif.backgroundColor = _globalColorTable[lsd.backgroundColorIndex];
		}
		readBlock();
		_graphicControlExtension = null;
		_globalColorTable = null;
		_input = null;
		return gif;
	}

	private function readHeader():Bool
	{
		var ok = _input.readUTFBytes(3) == "GIF";
		if (ok)
		{
			var v = _input.readUTFBytes(3);
			gif.version = v == "87a" ? GIF87a : GIF89a;
		}
		return ok;
	}

	private function readBlock():Void
	{
		while (true)
		{
			var id = _input.readByte();
			switch (id)
			{
				case 0x2C: readImage();
				case 0x21: readExtension();
				case 0x3B: return;
			}
		}
	}

	private function readExtension():Void
	{
		var type = _input.readByte();
		switch (type)
		{
			case 0xF9:
				#if yagp_strict_gif_version_check
				if (gif.version == GIF87a) { skipBlock(); return; }
				#end
				_graphicControlExtension = new GraphicsControl(_input);
			case 0xFF: readApplicationExtension();
			default: skipBlock();
		}
	}

	private function readApplicationExtension():Void
	{
		#if yagp_strict_gif_version_check
		if (gif.version == GIF87a) { skipBlock(); return; }
		#end
		_input.position++;
		var name = _input.readUTFBytes(8);
		_input.readUTFBytes(3);
		if (name == "NETSCAPE") gif.netscape = new NetscapeExtension(_input);
		else skipBlock();
	}

	private function readImage():Void
	{
		var desc = new ImageDescriptor(_input);
		var table = desc.localColorTable ? readColorTable(desc.localColorTableSize) : _globalColorTable;
		if (table == null) throw "No color table";
		var decoder = new GraphicsDecoder(_input, desc);
		gif.frames.push(new GifFrame(table, desc, decoder, _graphicControlExtension));
		_graphicControlExtension = null;
	}

	private function readColorTable(count:Int):Array<Int>
	{
		var out = new Array<Int>();
		for (i in 0...count)
			out[i] = 0xFF000000 | (_input.readByte() << 16) | (_input.readByte() << 8) | _input.readByte();
		return out;
	}

	private function skipBlock():Void
	{
		var size = 0;
		do
		{
			size = _input.readByte();
			_input.position += size;
		}
		while (size != 0);
	}
}