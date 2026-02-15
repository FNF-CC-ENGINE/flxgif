package flxgif;

import com.yagp.GifDecoder;
import com.yagp.GifPlayer;
import com.yagp.GifRenderer;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxDestroyUtil;
import flixel.FlxSprite;
import flixel.FlxG;
import flxgif.FlxGifAsset;
import openfl.utils.Assets;
import openfl.utils.AssetType;
import openfl.utils.ByteArray;

import haxe.io.Bytes;

/**
 * `FlxGifSprite` is made for displaying gif files in HaxeFlixel as sprites.
 */
class FlxGifSprite extends FlxSprite
{
	/**
	 * The Gif Player (warning: can be `null`).
	 */
	public var player(default, null):GifPlayer;

	/**
	 * The Gif SpriteMap (warning: can be `null`).
	 */
	public var map(default, null):GifMap;
	
	/**
	 * Performance optimization settings for GIF playback.
	 * These settings help improve performance on low-end hardware.
	 */
	public var performanceMode:Bool = false;
	public var targetFPS:Float = 30.0;
	public var skipFrames:Bool = false;
	
	/**
	 * Whether to apply performance optimizations automatically based on GIF size.
	 * If true, large GIFs will automatically enable performance mode.
	 */
	public var autoPerformanceMode:Bool = true;
	
	/**
	 * Threshold for automatic performance mode (in pixels).
	 * GIFs larger than this will automatically enable performance mode.
	 */
	public var autoPerformanceThreshold:Int = 500000; // 500x500 pixels

	/**
	 * Enables/disables hardware acceleration via Tilemap.
	 * Default is true (enabled). Disable for large GIFs.
	 */
	public var useHardware(get, set):Bool;
	private var _useHardware:Bool = true;

	/**
	 * Global speed multiplier for the GIF animation. Default is 1.0 (normal speed).
	 * Values greater than 1.0 will speed up the animation, while values between 0.0 and 1.0 will slow it down.
	 */
	public var speed(get, set):Float;
	private var _speed:Float = 1.0;

	/**
	 * Creates a `FlxGifSprite` at a specified position with a specified gif.
	 *
	 * If none is provided, a 16x16 image of the HaxeFlixel logo is used.
	 *
	 * @param x The initial X position of the sprite.
	 * @param y The initial Y position of the sprite.
	 * @param simpleGif The gif you want to display.
	 */
	public function new(?x:Float = 0, ?y:Float = 0, ?simpleGif:FlxGifAsset):Void
	{
		super(x, y);

		if (simpleGif != null)
			loadGif(simpleGif);
	}

	/**
	 * Call this function to load a gif.
	 *
	 * @param gif The gif you want to use.
	 * @param asMap Whether the gif should be loaded as a spritemap to be animated or not.
	 * @param performanceOptions Optional performance settings for the GIF player.
	 *                          If not provided, uses current class properties.
	 *
	 * @return This `FlxGifSprite` instance (nice for chaining stuff together, if you're into that).
	 */
	public function loadGif(gif:FlxGifAsset, asMap:Bool = false, ?performanceOptions:GifPerformanceOptions):FlxGifSprite
	{
		if (performanceOptions != null) applyPerformanceOptions(performanceOptions);
		
		player?.dispose(true);
		player = null;
		
		if (map != null) {
			map.data = FlxDestroyUtil.dispose(map.data);
			map = null;
		}

		function getBytesFromGif(gif:FlxGifAsset):ByteArray {
			if ((gif is ByteArrayData)) return gif;
			if ((gif is Bytes)) return ByteArray.fromBytes(gif);
			
			var path:String = Std.string(gif);
			var bytes:ByteArray = Assets.exists(path, AssetType.BINARY) ? Assets.getBytes(path) : null;
			
			#if sys
			if (bytes == null && sys.FileSystem.exists(path))
				bytes = ByteArray.fromBytes(sys.io.File.getBytes(path));
			#end
			
			if (bytes == null) {
				FlxG.log.error('Could not load GIF data from: $path');
				return null;
			}
			return bytes;
		}

		if (!asMap)
		{
			var bytes = getBytesFromGif(gif);
			if (bytes == null) return this;
			
			var gifData = GifDecoder.parseByteArray(bytes);
			if (autoPerformanceMode && gifData != null) {
				performanceMode = (gifData.width * gifData.height * gifData.frames.length) > autoPerformanceThreshold;
			}
			
			player = new GifPlayer(gifData);
			if (player != null) {
				player.performanceMode = performanceMode;
				player.targetFPS = targetFPS;
				player.skipFrames = skipFrames;
			}

			loadGraphic(FlxGraphic.fromBitmapData(player.data, false, null, false));
		}
		else
		{
			var bytes = getBytesFromGif(gif);
			if (bytes == null) return this;
			
			map = GifRenderer.createMap(GifDecoder.parseByteArray(bytes));
			loadGraphic(FlxGraphic.fromBitmapData(map.data, false, null, false), true, map.width, map.height);
		}

		return this;
	}
	
	/**
	 * Apply performance settings to the GIF player.
	 * This method can be called after loading a GIF to change performance settings.
	 * 
	 * @param options Performance options to apply
	 */
	public function applyPerformanceOptions(options:GifPerformanceOptions):Void
	{
		this.performanceMode = options.performanceMode;
		this.targetFPS = options.targetFPS;
		this.skipFrames = options.skipFrames;
		this.autoPerformanceMode = options.autoPerformanceMode;
		
		if (options.autoPerformanceThreshold != null) {
			this.autoPerformanceThreshold = options.autoPerformanceThreshold;
		}
		
		// Update player if it exists
		if (player != null) {
			player.performanceMode = performanceMode;
			player.targetFPS = targetFPS;
			player.skipFrames = skipFrames;
		}
	}
	
	/**
	 * Set individual performance settings.
	 * 
	 * @param performanceMode Enable performance optimizations
	 * @param targetFPS Target frames per second (default: 30)
	 * @param skipFrames Skip frames if falling behind
	 */
	public function setPerformanceSettings(
		performanceMode:Bool = false,
		targetFPS:Float = 30.0,
		skipFrames:Bool = false
	):Void
	{
		this.performanceMode = performanceMode;
		this.targetFPS = targetFPS;
		this.skipFrames = skipFrames;
		
		if (player != null) {
			player.performanceMode = performanceMode;
			player.targetFPS = targetFPS;
			player.skipFrames = skipFrames;
		}
	}
	
	/**
	 * Enable automatic performance optimization.
	 * 
	 * @param enabled Whether to enable auto performance mode
	 * @param threshold Pixel threshold for auto-enabling (default: 500000)
	 */
	public function setAutoPerformance(enabled:Bool = true, ?threshold:Int):Void
	{
		this.autoPerformanceMode = enabled;
		if (threshold != null) {
			this.autoPerformanceThreshold = threshold;
		}
	}
	
	/**
	 * Get current performance statistics.
	 * Only works when using GifPlayer (not sprite map).
	 * 
	 * @return Performance information or null if not available
	 */
	public function getPerformanceInfo():Dynamic
	{
		if (player != null) {
			return player.getPerformanceInfo();
		}
		return null;
	}

	private function get_useHardware():Bool
	{
		return _useHardware;
	}

	private function set_useHardware(value:Bool):Bool
	{
		_useHardware = value;
		if (player != null) player.useHardware = value;
		return value;
	}

	private inline function get_speed():Float
	{
		return _speed;
	}

	private function set_speed(v:Float):Float
	{
		_speed = v <= 0 ? 0.0001 : v;
		if (player != null) player.speed = _speed;
		return _speed;
	}

	public override function update(elapsed:Float):Void
	{
		if (player != null)
			player.update(elapsed);

		super.update(elapsed);
	}

	public override function destroy():Void
	{
		super.destroy();

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
	}
}

/**
 * Performance options for GIF playback.
 */
typedef GifPerformanceOptions = {
	/**
	 * Enable performance optimizations for low-end hardware.
	 */
	var performanceMode:Bool;
	
	/**
	 * Target frames per second for animation playback.
	 * Lower values reduce CPU/GPU usage.
	 */
	var targetFPS:Float;
	
	/**
	 * Skip frames if falling behind in animation.
	 * Helps maintain smooth playback on slow systems.
	 */
	var skipFrames:Bool;
	
	/**
	 * Automatically enable performance mode based on GIF size.
	 */
	var autoPerformanceMode:Bool;
	
	/**
	 * Pixel threshold for automatic performance mode.
	 * GIFs larger than width*height*frames > threshold will auto-enable performance mode.
	 */
	@:optional var autoPerformanceThreshold:Int;
}