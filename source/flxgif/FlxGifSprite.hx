package flxgif;

import com.yagp.GifDecoder;
import com.yagp.GifPlayer;
import com.yagp.GifRenderer;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxDestroyUtil;
import flixel.FlxSprite;
import flxgif.FlxGifAsset;
import haxe.io.Bytes;
import openfl.utils.Assets;
import openfl.utils.ByteArray;

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
	public var forceCache:Bool = true;
	
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
		if (performanceOptions != null) {
			applyPerformanceOptions(performanceOptions);
		}
		
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

		if (!asMap)
		{
			var gifData:com.yagp.Gif = null;
			
			if ((gif is ByteArrayData))
				gifData = GifDecoder.parseByteArray(gif);
			else if ((gif is Bytes))
				gifData = GifDecoder.parseByteArray(ByteArray.fromBytes(gif));
			else
				gifData = GifDecoder.parseByteArray(Assets.getBytes(Std.string(gif)));
			
			// Auto-detect if we should enable performance mode
			if (autoPerformanceMode && gifData != null) {
				var totalPixels = gifData.width * gifData.height * gifData.frames.length;
				if (totalPixels > autoPerformanceThreshold) {
					performanceMode = true;
					forceCache = true;
				}
			}
			
			player = new GifPlayer(gifData);
			
			// Apply performance settings to player
			if (player != null) {
				player.performanceMode = performanceMode;
				player.targetFPS = targetFPS;
				player.skipFrames = skipFrames;
				player.forceCache = forceCache;
			}

			loadGraphic(FlxGraphic.fromBitmapData(player.data, false, null, false));
		}
		else
		{
			if ((gif is ByteArrayData))
				map = GifRenderer.createMap(GifDecoder.parseByteArray(gif));
			else if ((gif is Bytes))
				map = GifRenderer.createMap(GifDecoder.parseByteArray(ByteArray.fromBytes(gif)));
			else
				map = GifRenderer.createMap(GifDecoder.parseByteArray(Assets.getBytes(Std.string(gif))));

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
		this.forceCache = options.forceCache;
		this.autoPerformanceMode = options.autoPerformanceMode;
		
		if (options.autoPerformanceThreshold != null) {
			this.autoPerformanceThreshold = options.autoPerformanceThreshold;
		}
		
		// Update player if it exists
		if (player != null) {
			player.performanceMode = performanceMode;
			player.targetFPS = targetFPS;
			player.skipFrames = skipFrames;
			player.forceCache = forceCache;
		}
	}
	
	/**
	 * Set individual performance settings.
	 * 
	 * @param performanceMode Enable performance optimizations
	 * @param targetFPS Target frames per second (default: 30)
	 * @param skipFrames Skip frames if falling behind
	 * @param forceCache Force cache usage
	 */
	public function setPerformanceSettings(
		performanceMode:Bool = false,
		targetFPS:Float = 30.0,
		skipFrames:Bool = false,
		forceCache:Bool = true
	):Void
	{
		this.performanceMode = performanceMode;
		this.targetFPS = targetFPS;
		this.skipFrames = skipFrames;
		this.forceCache = forceCache;
		
		if (player != null) {
			player.performanceMode = performanceMode;
			player.targetFPS = targetFPS;
			player.skipFrames = skipFrames;
			player.forceCache = forceCache;
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
	 * Force cache usage for all frames.
	 * Increases memory usage but improves performance.
	 */
	var forceCache:Bool;
	
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

/**
 * Helper class for creating predefined performance profiles.
 */
class GifPerformanceProfiles
{
	/**
	 * High performance profile for modern systems.
	 * Uses maximum quality with 60 FPS target.
	 */
	public static var HIGH:Array<Dynamic> = [
		{performanceMode: false, targetFPS: 60.0, skipFrames: false, forceCache: true, autoPerformanceMode: false}
	];
	
	/**
	 * Balanced profile for most systems.
	 * Good balance between quality and performance.
	 */
	public static var BALANCED:Array<Dynamic> = [
		{performanceMode: true, targetFPS: 30.0, skipFrames: false, forceCache: true, autoPerformanceMode: true, autoPerformanceThreshold: 500000}
	];
	
	/**
	 * Performance profile for low-end systems.
	 * Prioritizes smooth playback over visual quality.
	 */
	public static var LOW:Array<Dynamic> = [
		{performanceMode: true, targetFPS: 20.0, skipFrames: true, forceCache: true, autoPerformanceMode: true, autoPerformanceThreshold: 250000}
	];
	
	/**
	 * Ultra performance profile for very weak hardware.
	 * Maximum performance optimizations.
	 */
	public static var ULTRA_PERFORMANCE:Array<Dynamic> = [
		{performanceMode: true, targetFPS: 15.0, skipFrames: true, forceCache: true, autoPerformanceMode: true, autoPerformanceThreshold: 100000}
	];
}