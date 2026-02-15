package flxgif;

import flxgif.FlxGifSprite.GifPerformanceOptions;

/**
 * Helper class for creating predefined performance profiles.
 */
class GifPerformanceProfiles
{
	/**
	 * High performance profile for modern systems.
	 * Uses maximum quality with 60 FPS target.
	 */
	public static final HIGH:GifPerformanceOptions = {
		performanceMode: false,
		targetFPS: 60.0,
		skipFrames: false,
		autoPerformanceMode: false
	};

	/**
	 * Balanced profile for most systems.
	 * Good balance between quality and performance.
	 */
	public static final BALANCED:GifPerformanceOptions = {
		performanceMode: true,
		targetFPS: 30.0,
		skipFrames: false,
		autoPerformanceMode: true,
		autoPerformanceThreshold: 500000
	};

	/**
	 * Performance profile for low-end systems.
	 * Prioritizes smooth playback over visual quality.
	 */
	public static final LOW:GifPerformanceOptions = {
		performanceMode: true,
		targetFPS: 20.0,
		skipFrames: true,
		autoPerformanceMode: true,
		autoPerformanceThreshold: 250000
	};

	/**
	 * Ultra performance profile for very weak hardware.
	 * Maximum performance optimizations.
	 */
	public static final ULTRA_PERFORMANCE:GifPerformanceOptions = {
		performanceMode: true,
		targetFPS: 15.0,
		skipFrames: true,
		autoPerformanceMode: true,
		autoPerformanceThreshold: 100000
	};
}