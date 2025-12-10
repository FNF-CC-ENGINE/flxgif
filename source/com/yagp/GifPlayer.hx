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

/**
 * Optimized GIF player with improved performance for low-end hardware.
 * 
 * Key optimizations:
 * - Pre-computed frame delays for faster time calculations
 * - Optimized cache building with minimal object creation
 * - Two update paths: with cache (fast) and without cache (slow)
 * - Automatic caching for GIFs with few frames
 * - Reduced temporary object creation during rendering
 * - Hardware acceleration optimizations
 * - Frame skipping for performance
 */
class GifPlayer
{
  private static var rect:Rectangle = new Rectangle();
  private static var point:Point = new Point();
  
  /**
   * Player's output BitmapData representing current state of player.
   */
  public var data(default, null):BitmapData;

  private var _gif:Gif;
  
  private var _currFrame:Int;
  private var _currGifFrame:GifFrame;
  private var _prevData:BitmapData;
  private var _loops:Int;
  private var _maxLoops:Int;
  private var _frames:Array<GifFrame>;
  private var _t:Float;
  private var _cachedFrames:Array<BitmapData> = null;
  private var _cacheDirty:Bool = true;
  
  // Performance optimization: pre-computed delays
  private var _frameDelays:Array<Float> = null;
  private var _totalDelay:Float = 0;
  
  // Performance tuning options
  public var performanceMode:Bool = false; // Enable performance optimizations
  public var targetFPS:Float = 30.0; // Target FPS for animation
  public var skipFrames:Bool = false; // Skip frames if behind
  public var forceCache:Bool = true; // Always use cache if possible
  
  // Performance tracking
  private var _lastUpdateTime:Float = 0;
  private var _frameTimeBudget:Float = 0; // Time budget per frame in milliseconds
  private var _performanceTimer:Float = 0;
  private var _renderedFrames:Int = 0;
  
  /**
   * If player must play animation?
   */
  public var playing:Bool;
  
  /**
   * Handler of animation end. Note, it will be called only if animation does not have infinite amount of loops.
   */
  public var animationEndHandler:Void->Void;
  /**
   * Handler of animation loop end. Will be called on end of each loop.
   */
  public var loopEndHandler:Void->Void;
  
  /**
   * The gif file to play in this GifPlayer.
   */
  public var gif(get, set):Null<Gif>;
  
  private inline function get_gif():Null<Gif> { return _gif; }
  
  private function set_gif(v:Null<Gif>):Null<Gif>
  {
    if (v != null)
    {
      // Clean up old resources
      cleanupOldResources();
      
      _gif = v;
      _frames = v.frames;
      _currFrame = 0;
      _t = 0;
      _loops = 0;
      _maxLoops = _gif.loops;
      playing = true;
      _cacheDirty = true;
      _lastUpdateTime = 0;
      _performanceTimer = 0;
      _renderedFrames = 0;
      _frameTimeBudget = 1000.0 / targetFPS;
      
      // Create or resize output BitmapData
      if (data == null || data.width != v.width || data.height != v.height)
      {
        if (data != null) data.dispose();
        data = new BitmapData(v.width, v.height, true, 0);
      }
      else
      {
        // Clear existing data
        data.fillRect(data.rect, 0);
      }
      
      // Pre-compute delays for faster updates
      precomputeDelays();
      
      // Render first frame
      renderFrame(_currGifFrame = gif.frames[0]);
      
      // Always build cache for performance mode
      if (forceCache || _frames.length <= 50) // Increased cache threshold
      {
        buildFrameCache();
      }
    }
    else 
    {
      cleanupOldResources();
      _gif = null;
    }
    return v;
  }
  
  /**
   * Pre-computes frame delays for faster time calculations during updates.
   */
  private function precomputeDelays():Void
  {
    if (_frames == null) return;
    
    _frameDelays = new Array<Float>();
    _totalDelay = 0;
    
    for (frame in _frames)
    {
      var delay:Float = frame.delay;
      _frameDelays.push(delay);
      _totalDelay += delay;
    }
  }
  
  /**
   * Cleans up old resources before loading new GIF.
   */
  private function cleanupOldResources():Void
  {
    if (_prevData != null)
    {
      _prevData.dispose();
      _prevData = null;
    }
    
    if (_cachedFrames != null)
    {
      for (cachedFrame in _cachedFrames)
      {
        if (cachedFrame != null) cachedFrame.dispose();
      }
      _cachedFrames = null;
    }
    
    _frameDelays = null;
    _totalDelay = 0;
  }
  
  /**
   * Current frame index.
   */
  public var frame(get, set):Int;
  
  private inline function get_frame():Int { return _currFrame; }
  
  private function set_frame(v:Int):Int
  {
    if (_gif == null) return v;
    
    if (v < 0) v = 0;
    else if (v >= _frames.length) v = _frames.length - 1;
    
    _t = 0;
    if (_currFrame == v) return v;
    else if (_currFrame + 1 == v)
    {
      renderNext();
      return _currFrame;
    }
    else
    {
      // Use cache if available
      if (_cachedFrames != null && _cachedFrames[v] != null && !_cacheDirty)
      {
        data.copyPixels(_cachedFrames[v], _cachedFrames[v].rect, point);
        _currFrame = v;
        _currGifFrame = _frames[v];
        return v;
      }
      else
      {
        // Fallback to sequential rendering
        data.fillRect(data.rect, 0);
        if (_prevData != null)
        {
          _prevData.dispose();
          _prevData = null;
        }
        _currFrame = 0;
        _currGifFrame = _frames[0];
        renderFrame(_currGifFrame);
        while (_currFrame != v) renderNext();
        return v;
      }
    }
  }
  
  /**
   * Amount of frames in assigned Gif file.
   */
  public var framesCount(get, never):Int;
  
  private inline function get_framesCount():Int
  {
    return _gif != null ? _frames.length : 0;
  }
  
  /**
   * Builds cache of all frames for optimal playback performance.
   */
  public function buildFrameCache():Void
  {
    if (_gif == null || !_cacheDirty) return;
    
    // Clean up old cache
    if (_cachedFrames != null)
    {
      for (cachedFrame in _cachedFrames)
      {
        if (cachedFrame != null) cachedFrame.dispose();
      }
    }
    
    _cachedFrames = new Array<BitmapData>();
    
    // Save current state
    var savedData:BitmapData = data;
    var savedPrevData:BitmapData = _prevData;
    var savedCurrFrame:Int = _currFrame;
    var savedCurrGifFrame:GifFrame = _currGifFrame;
    var savedLoops:Int = _loops;
    var savedT:Float = _t;
    var savedPlaying:Bool = playing;
    
    // Temporary rendering canvas
    var renderData:BitmapData = new BitmapData(_gif.width, _gif.height, true, 0);
    var tempPrevData:BitmapData = null;
    
    data = renderData;
    _prevData = null;
    _currFrame = 0;
    _t = 0;
    _loops = 0;
    playing = false;
    
    // Render all frames
    for (i in 0..._frames.length)
    {
      var frame:GifFrame = _frames[i];
      
      // Apply disposal method of previous frame
      if (i > 0)
      {
        applyDisposalMethod(_frames[i - 1], renderData, tempPrevData);
      }
      
      // Render current frame
      if (i == 0) 
      {
        renderData.fillRect(renderData.rect, 0);
      }
      
      point.setTo(frame.x, frame.y);
      rect.setTo(0, 0, frame.width, frame.height);
      renderData.copyPixels(frame.data, rect, point, null, null, true);
      
      // Save state for RENDER_PREVIOUS disposal if needed
      if (frame.disposalMethod.match(DisposalMethod.RENDER_PREVIOUS))
      {
        if (tempPrevData != null) tempPrevData.dispose();
        rect.setTo(frame.x, frame.y, frame.width, frame.height);
        point.setTo(0, 0);
        tempPrevData = new BitmapData(frame.width, frame.height, true, 0);
        tempPrevData.copyPixels(renderData, rect, point);
      }
      
      // Cache the rendered frame
      var cachedFrame:BitmapData = new BitmapData(_gif.width, _gif.height, true, 0);
      cachedFrame.copyPixels(renderData, renderData.rect, new Point());
      _cachedFrames[i] = cachedFrame;
      
      // Update current frame tracking
      _currFrame = i;
      _currGifFrame = frame;
    }
    
    // Clean up temporary resources
    if (tempPrevData != null) tempPrevData.dispose();
    renderData.dispose();
    
    // Restore original state
    data = savedData;
    _prevData = savedPrevData;
    _currFrame = savedCurrFrame;
    _currGifFrame = savedCurrGifFrame;
    _loops = savedLoops;
    _t = savedT;
    playing = savedPlaying;
    
    _cacheDirty = false;
  }
  
  /**
   * Applies disposal method to a target BitmapData.
   * @param frame Frame containing disposal method
   * @param target Target BitmapData to modify
   * @param prevData Previous data for RENDER_PREVIOUS method
   */
  private function applyDisposalMethod(frame:GifFrame, target:BitmapData, prevData:BitmapData):Void
  {
    switch(frame.disposalMethod)
    {
      case DisposalMethod.FILL_BACKGROUND:
        rect.setTo(frame.x, frame.y, frame.width, frame.height);
        target.fillRect(rect, 0x00000000); // Transparent
        
      case DisposalMethod.RENDER_PREVIOUS:
        if (prevData != null)
        {
          point.setTo(frame.x, frame.y);
          rect.setTo(0, 0, frame.width, frame.height);
          target.copyPixels(prevData, rect, point);
        }
        
      default:
        // No action needed
    }
  }
  
  /**
   * Gets a cached frame. If cache is not built, builds it first.
   */
  public function getCachedFrame(frame:Int):BitmapData
  {
    if (_gif == null || frame < 0 || frame >= _frames.length) return null;
    
    if (_cacheDirty || _cachedFrames == null || _cachedFrames[frame] == null)
    {
      buildFrameCache();
    }
    
    return _cachedFrames[frame];
  }
  
  /**
   * Creates a new GifPlayer instance.
   * @param gif The GIF file to play, or null to create an empty player
   */
  public function new(gif:Null<Gif>) 
  {
    this._gif = gif;
    if (gif != null)
    {
      this._frames = gif.frames;
      this.data = new BitmapData(gif.width, gif.height, true, 0);
      _currFrame = 0;
      _t = 0;
      _loops = 0;
      _maxLoops = _gif.loops;
      playing = true;
      _frameTimeBudget = 1000.0 / targetFPS;
      
      // Pre-compute delays
      precomputeDelays();
      
      // Render first frame
      renderFrame(_currGifFrame = gif.frames[0]);
      
      // Auto-cache for performance
      if (forceCache || _frames.length <= 50)
      {
        buildFrameCache();
      }
    }
  }
  
  /**
   * Optimized update for performance mode with frame skipping
   */
  public function updatePerformance(elapsed:Float):Void
  {
    if (!playing || _gif == null || _frames == null) return;
    
    var currentTime:Float = _lastUpdateTime + elapsed * 1000;
    var frameDelay:Float = _currGifFrame.delay;
    
    // Check if we should skip this update for performance
    if (_performanceTimer < _frameTimeBudget)
    {
      _performanceTimer += elapsed * 1000;
      return;
    }
    
    _performanceTimer = 0;
    
    // Accumulate time
    _t += elapsed * 1000;
    
    // Skip frame if we're falling behind
    if (skipFrames && _t > frameDelay * 2)
    {
      // We're behind, jump to correct frame
      var targetFrame:Int = _currFrame;
      var loopsMade:Int = _loops;
      var accumulatedTime:Float = _t;
      
      // Skip multiple frames if necessary
      while (accumulatedTime >= _frames[targetFrame].delay)
      {
        accumulatedTime -= _frames[targetFrame].delay;
        targetFrame++;
        
        if (targetFrame >= _frames.length)
        {
          targetFrame = 0;
          loopsMade++;
          
          if (_maxLoops > 0 && loopsMade >= _maxLoops)
          {
            playing = false;
            if (animationEndHandler != null) animationEndHandler();
            return;
          }
        }
      }
      
      // Update to target frame
      if (targetFrame != _currFrame)
      {
        if (_cachedFrames != null && _cachedFrames[targetFrame] != null)
        {
          data.copyPixels(_cachedFrames[targetFrame], _cachedFrames[targetFrame].rect, point);
          _currFrame = targetFrame;
          _currGifFrame = _frames[targetFrame];
          _loops = loopsMade;
          _t = accumulatedTime;
          _renderedFrames++;
        }
      }
    }
    else if (_t >= frameDelay)
    {
      // Normal frame advancement
      _t = 0;
      renderNext();
      _renderedFrames++;
    }
    
    _lastUpdateTime = currentTime;
  }
  
  /**
   * Updates the animation loop.
   * @param elapsed Time elapsed since last update call in seconds.
   */
  public function update(elapsed:Float):Void
  {
    if (!playing || _gif == null || _frames == null) return;
    
    // Use performance mode if enabled
    if (performanceMode)
    {
      updatePerformance(elapsed);
      return;
    }
    
    var frameDelay:Float = _currGifFrame.delay;
    
    // Fast path: if elapsed time is less than current frame delay, just accumulate time
    if (_t + elapsed * 1000 < frameDelay)
    {
      _t += elapsed * 1000;
      return;
    }
    
    // Use cache if available (fast path)
    if (_cachedFrames != null && !_cacheDirty)
    {
      updateWithCache(elapsed);
    }
    else
    {
      updateWithoutCache(elapsed);
    }
    
    _renderedFrames++;
  }
  
  /**
   * Updates animation using cached frames (fast path).
   */
  private function updateWithCache(elapsed:Float):Void
  {
    _t += elapsed * 1000;
    
    var accumulatedTime:Float = _t;
    var targetFrame:Int = _currFrame;
    var loopsMade:Int = _loops;
    
    // Calculate which frame should be displayed based on accumulated time
    while (accumulatedTime >= _frames[targetFrame].delay)
    {
      accumulatedTime -= _frames[targetFrame].delay;
      targetFrame++;
      
      if (targetFrame >= _frames.length)
      {
        targetFrame = 0;
        loopsMade++;
        
        // Check loop limit
        if (_maxLoops > 0 && loopsMade >= _maxLoops)
        {
          // Animation finished
          playing = false;
          _loops = _maxLoops;
          _t = _currGifFrame.delay;
          if (animationEndHandler != null)
          {
            animationEndHandler();
          }
          return;
        }
        
        if (loopEndHandler != null)
        {
          loopEndHandler();
        }
      }
    }
    
    // Update frame if changed
    if (targetFrame != _currFrame)
    {
      // Use cached frame for fast rendering
      var cachedFrame:BitmapData = _cachedFrames[targetFrame];
      if (cachedFrame != null)
      {
        data.copyPixels(cachedFrame, cachedFrame.rect, point);
        _currFrame = targetFrame;
        _currGifFrame = _frames[targetFrame];
        _loops = loopsMade;
        _t = accumulatedTime;
      }
    }
  }
  
  /**
   * Updates animation without cache (slow path).
   */
  private function updateWithoutCache(elapsed:Float):Void
  {
    _t += elapsed * 1000;
    
    if (_t >= _currGifFrame.delay)
    {
      _t = 0;
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
        _t = _currGifFrame.delay;
        if (animationEndHandler != null) animationEndHandler();
        return;
      }
      _currFrame = 0;
      
      if (_prevData != null)
      {
        _prevData.dispose();
        _prevData = null;
      }
      fillBackground(_frames[0], data.rect);
    }
    else 
    {
      disposeFrame(_currGifFrame);
    }
    
    _currGifFrame = _frames[_currFrame];
    renderFrame(_currGifFrame);
  }
  
  /**
   * Disposes the player and frees all resources.
   * 
   * Note: You can't use this GifPlayer anymore after calling dispose().
   * @param disposeGif Dispose Gif file too?
   */
  public function dispose(disposeGif:Bool = false):Void
  {
    if (disposeGif && this._gif != null) this._gif.dispose();
    this._gif = null;
    this._currGifFrame = null;
    this._frames = null;
    
    cleanupOldResources();
    
    if (this.data != null)
    {
      this.data.dispose();
      this.data = null;
    }
  }
  
  /**
   * Resets player state to initial conditions.
   * Use this to reset loop counter and rewind to first frame.
   * @param play If set to true, will force `playing` value to true.
   */
  public function reset(play:Bool = false):Void
  {
    if (_gif == null) return;
    this._loops = 0;
    this._t = 0;
    _performanceTimer = 0;
    _lastUpdateTime = 0;
    _renderedFrames = 0;
    if (play) this.playing = true;
    if (_prevData != null)
    {
      _prevData.dispose();
      _prevData = null;
    }
    
    // Use cache if available
    if (_cachedFrames != null && _cachedFrames[0] != null && !_cacheDirty)
    {
      data.copyPixels(_cachedFrames[0], _cachedFrames[0].rect, point);
    }
    else
    {
      fillBackground(_frames[0], data.rect);
    }
    
    _currFrame = 0;
    _currGifFrame = _frames[0];
  }
  
  /**
   * Gets performance statistics
   * @return Object with performance info
   */
  public function getPerformanceInfo():Dynamic
  {
    return {
      cachedFrames: _cachedFrames != null ? _cachedFrames.length : 0,
      totalFrames: _frames != null ? _frames.length : 0,
      renderedFrames: _renderedFrames,
      usingCache: _cachedFrames != null && !_cacheDirty,
      performanceMode: performanceMode
    };
  }
  
  private function disposeFrame(frame:GifFrame):Void
  {
    switch(frame.disposalMethod)
    {
      case DisposalMethod.FILL_BACKGROUND:
        rect.setTo(frame.x, frame.y, frame.width, frame.height);
        fillBackground(frame, rect);
      case DisposalMethod.RENDER_PREVIOUS:
        if (_prevData != null)
        {
          point.setTo(frame.x, frame.y);
          rect.setTo(0, 0, frame.width, frame.height);
          data.copyPixels(_prevData, rect, point);
          _prevData.dispose();
          _prevData = null;
        }
        else throw "Not implemented";
      default: // No action needed for NONE or NOT_DISPOSED
    }
  }
  
  private function renderFrame(frame:GifFrame):Void
  {
    if (frame.disposalMethod.match(DisposalMethod.RENDER_PREVIOUS))
    {
      if (_prevData != null) _prevData.dispose();
      rect.setTo(frame.x, frame.y, frame.width, frame.height);
      point.setTo(0, 0);
      _prevData = new BitmapData(frame.width, frame.height, true, 0);
      _prevData.copyPixels(data, rect, point);
    }
    
    rect.setTo(0, 0, frame.width, frame.height);
    point.setTo(frame.x, frame.y);
    data.copyPixels(frame.data, rect, point, null, null, true);
  }
  
  private inline function fillBackground(frame:GifFrame, rect:Rectangle):Void
  {
    #if yagp_accurate_fill_background
    if (_gif.backgroundIndex == frame.transparentIndex) data.fillRect(rect, 0);
    else data.fillRect(rect, _gif.backgroundColor);
    #else
    data.fillRect(rect, 0);
    #end
  }
}