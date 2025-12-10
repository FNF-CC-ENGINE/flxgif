package flxgif;

#if !flixel_addons
#error 'Your project must use flixel-addons in order to use this class.'
#end
import com.yagp.GifDecoder;
import com.yagp.GifPlayer;
import com.yagp.GifRenderer;

import flxgif.FlxGifAsset;
import flxgif.FlxGifSprite.GifPerformanceOptions;
import flixel.addons.display.FlxBackdrop;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxAxes;
import flixel.util.FlxDestroyUtil;
import openfl.utils.Assets;
import openfl.utils.ByteArray;
import haxe.io.Bytes;

/**
 * `FlxGifBackdrop` is made for showing infinitely scrolling gif backgrounds using FlxBackdrop.
 */
class FlxGifBackdrop extends FlxBackdrop
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
	 * Creates an instance of the `FlxGifBackdrop` class, used to create infinitely scrolling gif backgrounds.
	 *
	 * @param gif The gif you want to use for the backdrop.
	 * @param repeatAxes The axes on which to repeat. The default, `XY` will tile the entire camera.
	 * @param spacingX Amount of spacing between tiles on the X axis.
	 * @param spacingY Amount of spacing between tiles on the Y axis.
	 */
	#if (flixel_addons >= version("3.2.1"))
	public function new(?gif:FlxGifAsset, repeatAxes = XY, spacingX = 0.0, spacingY = 0.0):Void
	{
		super(repeatAxes, spacingX, spacingY);

		if (gif != null)
			loadGif(gif);
	}
	#else
	public function new(?gif:FlxGifAsset, repeatAxes = XY, spacingX = 0, spacingY = 0):Void
	{
		super(repeatAxes, spacingX, spacingY);

		if (gif != null)
			loadGif(gif);
	}
	#end

	/**
	 * Call this function to load a gif.
	 *
	 * @param gif The gif you want to use.
	 * @param asMap Whether the gif should be loaded as a spritemap to be animated or not.
	 * @param performanceOptions Optional performance settings for the GIF player.
	 *                          If not provided, uses current class properties.
	 *
	 * @return This `FlxGifBackdrop` instance (nice for chaining stuff together, if you're into that).
	 */
	public function loadGif(gif:FlxGifAsset, asMap:Bool = false, ?performanceOptions:GifPerformanceOptions):FlxGifBackdrop
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