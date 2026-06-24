package flxgif;

#if !flixel_addons
#error "Your project must use flixel-addons in order to use this class."
#end

import com.yagp.Gif;
import com.yagp.GifDecoder;
import com.yagp.GifRenderer.GifMap;
import com.yagp.GifPlayer;
import com.yagp.GifRenderer;
import flixel.FlxG;
import flixel.addons.display.FlxBackdrop;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxAxes;
import flixel.util.FlxDestroyUtil;
import haxe.io.Bytes;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import openfl.utils.ByteArray;

/**
 * `FlxGifBackdrop` displays scrolling GIF backgrounds using `FlxBackdrop`.
 *
 * It supports:
 * - live mode: animated BitmapData through `GifPlayer`
 * - map mode: spritesheet playback with original GIF delays
 */
class FlxGifBackdrop extends FlxBackdrop
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
	 * Whether the backdrop should loop the GIF.
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

	private var _frameGraphics:Array<FlxGraphic>;

	/**
	 * Creates a GIF backdrop.
	 *
	 * @param gif Optional GIF asset to load immediately.
	 * @param repeatAxes Axes on which to repeat.
	 * @param spacingX X spacing between repeated tiles.
	 * @param spacingY Y spacing between repeated tiles.
	 */
	#if (flixel_addons >= version("3.2.1"))
	public function new(?gif:FlxGifAsset, repeatAxes:FlxAxes = FlxAxes.XY, spacingX = 0.0, spacingY = 0.0):Void
	{
		super(repeatAxes, spacingX, spacingY);

		if (gif != null)
			loadGif(gif);
	}
	#else
	public function new(?gif:FlxGifAsset, repeatAxes:FlxAxes = FlxAxes.XY, spacingX = 0, spacingY = 0):Void
	{
		super(repeatAxes, spacingX, spacingY);

		if (gif != null)
			loadGif(gif);
	}
	#end

	/**
	 * Loads a GIF.
	 *
	 * @param gif GIF asset, path, Bytes, or ByteArray.
	 * @param asMap If true, loads the GIF as a spritesheet. If false, uses live BitmapData playback.
	 * @return This backdrop.
	 */
	public function loadGif(gif:FlxGifAsset, asMap:Bool = false):FlxGifBackdrop
	{
		clearGif();

		var bytes = getBytesFromGif(gif);

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

		_frameGraphics = [];
		for (i in 0...player.framesCount)
		{
			final oldFrame = player.frame;
			player.frame = i;

			final frameGraphic = FlxGraphic.fromBitmapData(player.data, false, null, false);
			_frameGraphics.push(frameGraphic);
			player.frame = oldFrame;
		}

		loadGraphic(_frameGraphics[0]);
	}

	/**
	 * Loads decoded GIF as a spritesheet.
	 */
	private function loadAsMap(gif:Gif):Void
	{
		map = GifRenderer.createMap(gif, true);

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
			
			if (player.frame != oldFrame && _frameGraphics != null)
			{
				this.graphic = _frameGraphics[player.frame];
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

		if (_frameGraphics != null)
		{
			for (g in _frameGraphics)
			{
				FlxG.bitmap.remove(g);
			}
			_frameGraphics = null;
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