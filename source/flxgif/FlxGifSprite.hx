package flxgif;

import com.yagp.Gif;
import com.yagp.GifDecoder;
import com.yagp.GifRenderer.GifMap;
import com.yagp.GifPlayer;
import com.yagp.GifRenderer;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxDestroyUtil;
import haxe.io.Bytes;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import openfl.utils.ByteArray;

/**
 * `FlxGifSprite` displays GIF files in HaxeFlixel.
 *
 * It supports two modes:
 * - live mode: uses `GifPlayer` and updates one BitmapData
 * - map mode: converts GIF frames into a spritesheet and manually advances frames
 */
class FlxGifSprite extends FlxSprite
{
	/**
	 * Live GIF player. Only used when `asMap == false`.
	 */
	public var player(default, null):GifPlayer;

	/**
	 * GIF spritemap. Only used when `asMap == true`.
	 */
	public var map(default, null):GifMap;

	/**
	 * Global speed multiplier for GIF playback.
	 */
	public var speed(get, set):Float;
	private var _speed:Float = 1.0;

	/**
	 * Whether the sprite should loop the GIF.
	 */
	public var loop:Bool = true;

	/**
	 * Called when one loop finishes.
	 */
	public var loopEndHandler:Void->Void;

	/**
	 * Called when a non-looping GIF reaches the end.
	 */
	public var animationEndHandler:Void->Void;

	private var _gif:Gif;
	private var _isMapMode:Bool = false;
	private var _mapFrame:Int = 0;
	private var _mapTime:Float = 0;
	private var _mapLoops:Int = 0;
	private var _mapMaxLoops:Int = 0;

	/**
	 * Creates a `FlxGifSprite`.
	 *
	 * @param x Initial X position.
	 * @param y Initial Y position.
	 * @param gif Optional GIF asset to load immediately.
	 */
	public function new(?x:Float = 0, ?y:Float = 0, ?gif:FlxGifAsset):Void
	{
		super(x, y);

		if (gif != null)
			loadGif(gif);
	}

	/**
	 * Loads a GIF.
	 *
	 * @param gif GIF asset, path, Bytes, or ByteArray.
	 * @param asMap If true, loads the GIF as a spritesheet. If false, uses live BitmapData playback.
	 * @return This sprite.
	 */
	public function loadGif(gif:FlxGifAsset, asMap:Bool = false):FlxGifSprite
	{
		clearGif();

		final bytes = getBytesFromGif(gif);

		if (bytes == null)
			return this;

		try
		{
			_gif = GifDecoder.parseByteArray(bytes);
		}
		catch (e:Dynamic)
		{
			FlxG.log.error('Failed to decode GIF: $e');
			return this;
		}

		if (_gif == null || _gif.frames == null || _gif.frames.length == 0)
		{
			FlxG.log.error("Decoded GIF has no frames.");
			return this;
		}

		_isMapMode = asMap;
		_mapMaxLoops = _gif.loops;

		if (asMap)
			loadAsMap(_gif);
		else
			loadAsPlayer(_gif);

		return this;
	}

	/**
	 * Loads decoded GIF through `GifPlayer`.
	 */
	private function loadAsPlayer(gif:Gif):Void
	{
		player = new GifPlayer(gif);
		player.speed = _speed;
		player.loopEndHandler = loopEndHandler;
		player.animationEndHandler = animationEndHandler;

		loadGraphic(FlxGraphic.fromBitmapData(player.data, false, null, false));
		dirty = true;
	}

	/**
	 * Loads decoded GIF as a spritesheet.
	 *
	 * This mode avoids per-frame BitmapData copying during playback.
	 */
	private function loadAsMap(gif:Gif):Void
	{
		map = GifRenderer.createMap(gif);

		loadGraphic(
			FlxGraphic.fromBitmapData(map.data, false, null, false),
			true,
			map.width,
			map.height
		);

		final frames = [for (i in 0...map.delays.length) i];

		animation.add("__gif", frames, 30, true);
		animation.play("__gif");

		_mapFrame = 0;
		_mapTime = 0;
		_mapLoops = 0;

		dirty = true;
	}

	/**
	 * Reads bytes from supported GIF asset inputs.
	 */
	private function getBytesFromGif(gif:FlxGifAsset):ByteArray
	{
		final raw:Dynamic = gif;

		if (Std.isOfType(raw, Bytes))
			return ByteArray.fromBytes(cast raw);

		try
		{
			var byteArray:ByteArray = cast raw;
			if (byteArray != null)
				return byteArray;
		}
		catch (e:Dynamic) {}

		var path = Std.string(gif);
		var bytes:ByteArray = null;

		if (Assets.exists(path, AssetType.BINARY))
			bytes = Assets.getBytes(path);

		#if sys
		if (bytes == null && sys.FileSystem.exists(path))
			bytes = ByteArray.fromBytes(sys.io.File.getBytes(path));
		#end

		if (bytes == null)
			FlxG.log.error('Could not load GIF data from: $path');

		return bytes;
	}

	/**
	 * Updates GIF playback.
	 */
	override public function update(elapsed:Float):Void
	{
		if (player != null)
		{
			final oldFrame = player.frame;
			player.update(elapsed);
			
			if (oldFrame != player.frame)
			{
				dirty = true;
			}
		}

		super.update(elapsed);
	}

	/**
	 * Resets GIF playback.
	 */
	public function resetGif(play:Bool = true):Void
	{
		if (player != null)
		{
			player.reset(play);
			dirty = true;
			return;
		}

		if (map != null)
		{
			_mapFrame = 0;
			_mapTime = 0;
			_mapLoops = 0;

			if (animation != null)
				animation.frameIndex = 0;

			dirty = true;
		}
	}

	/**
	 * Stops GIF playback.
	 */
	public function pauseGif():Void
	{
		if (player != null)
			player.playing = false;
	}

	/**
	 * Resumes GIF playback.
	 */
	public function resumeGif():Void
	{
		if (player != null)
			player.playing = true;
	}

	/**
	 * Clears currently loaded GIF resources.
	 */
	public function clearGif():Void
	{
		if (player != null)
		{
			player.dispose(true);
			player = null;
		}

		if (map != null)
		{
			map.data = FlxDestroyUtil.dispose(map.data);
			map = null;
		}

		_gif = null;
		_isMapMode = false;
		_mapFrame = 0;
		_mapTime = 0;
		_mapLoops = 0;
		_mapMaxLoops = 0;
	}

	private inline function get_speed():Float
	{
		return _speed;
	}

	private function set_speed(value:Float):Float
	{
		_speed = value <= 0 ? 0.0001 : value;

		if (player != null)
			player.speed = _speed;

		return _speed;
	}

	override public function destroy():Void
	{
		clearGif();

		loopEndHandler = null;
		animationEndHandler = null;

		super.destroy();
	}
}