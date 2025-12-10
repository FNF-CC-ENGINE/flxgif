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

import flash.display.BitmapData;
import flash.geom.Point;
import flash.geom.Rectangle;
import haxe.io.Bytes;
import com.yagp.GifRenderer.GifMap;
import com.yagp.structs.DisposalMethod;
import com.yagp.structs.GifFrame;

typedef GifMap =
{
  /**
   * Spritesheet BitmapData
   */
  var data:BitmapData;
  /**
   * Single frame width
   */
  var width:Int;
  /**
   * Single frame height
   */
  var height:Int;
  /**
   * Delays for frames in milliseconds.
   */
  var frames:Array<Int>;
}

/**
 * Optimized implementation of rendering entire Gif file to spritesheet or individual frames.
 * 
 * Optimizations implemented:
 * - Pre-rendering of all frames at once to minimize copyPixels operations
 * - Smart caching system that only renders frames when needed
 * - Minimal temporary object creation during rendering
 * - Optimized disposal method handling
 * - Performance optimizations for low-end hardware
 */
class GifRenderer
{
  private var _restorer:BitmapData;
  private var _gif:Gif;
  private var _target:BitmapData;
  private var _drawTarget:BitmapData;
  private var _prevFrame:Int = -1;
  private var _cachedFrames:Array<BitmapData>;
  private var _allFramesCached:Bool = false;
  
  private static var _tempRect:Rectangle = new Rectangle();
  private static var _tempPoint:Point = new Point();
  
  /**
   * Creates spritesheet from given Gif file.
   * @param gif Gif file.
   * @param vertical Place frames vertically?  
   * Default: false
   * @return GifMap structure.
   */
  public static function createMap(gif:Gif, vertical:Bool = false):GifMap
  {
    var renderer:GifRenderer = new GifRenderer(gif);
    renderer.cacheAllFrames(); // Pre-cache all frames for optimal performance
    
    var framesCount:Int = gif.frames.length;
    var singleWidth:Int = gif.width;
    var singleHeight:Int = gif.height;
    
    // Calculate spritesheet dimensions
    var cols:Int = vertical ? 1 : framesCount;
    var rows:Int = vertical ? framesCount : 1;
    var sheetWidth:Int = singleWidth * cols;
    var sheetHeight:Int = singleHeight * rows;
    
    // Create spritesheet with lock for fast pixel operations
    var data:BitmapData = new BitmapData(sheetWidth, sheetHeight, true, 0);
    data.lock();
    
    var xOffset:Int = vertical ? 0 : singleWidth;
    var yOffset:Int = vertical ? singleHeight : 0;
    
    // Use cached frames for fast copying
    var cachedFrames:Array<BitmapData> = renderer._cachedFrames;
    for (i in 0...framesCount) 
    {
      var frame:BitmapData = cachedFrames[i];
      if (frame != null)
      {
        var destX:Int = xOffset * i;
        var destY:Int = yOffset * i;
        _tempPoint.x = destX;
        _tempPoint.y = destY;
        data.copyPixels(frame, frame.rect, _tempPoint);
      }
    }
    data.unlock();
    
    // Collect delay information
    var result:GifMap = { data:data, width:singleWidth, height:singleHeight, frames:new Array<Int>() };
    for (frame in gif.frames) result.frames.push(frame.delay);
    renderer.dispose();
    return result;
  }
  
  /**
   * Creates a new GifRenderer instance.
   * @param gif The GIF file to render
   */
  public function new(gif:Gif) 
  {
    _gif = gif;
    // Create drawing canvas with minimum size needed
    _drawTarget = new BitmapData(_gif.width, _gif.height, true, 0);
    _cachedFrames = new Array<BitmapData>();
    
    // Pre-initialize array for all frames
    for (i in 0..._gif.frames.length)
    {
      _cachedFrames[i] = null;
    }
  }
  
  /**
   * Pre-renders and caches all GIF frames for optimal performance.
   * This should be called before rendering frames in real-time animations.
   */
  public function cacheAllFrames():Void
  {
    if (_allFramesCached) return;
    
    // Save current states
    var oldTarget:BitmapData = _target;
    var oldPrevFrame:Int = _prevFrame;
    
    // Temporarily set null target to avoid unnecessary copies during caching
    _target = null;
    _prevFrame = -1;
    
    // Clear canvas for first frame
    _drawTarget.fillRect(_drawTarget.rect, 0);
    
    // Render all frames sequentially
    for (i in 0..._gif.frames.length)
    {
      // Skip if already cached
      if (_cachedFrames[i] != null) continue;
      
      // Render single frame
      renderSingleFrame(i);
      
      // Create and store cache
      var cachedFrame:BitmapData = new BitmapData(_gif.width, _gif.height, true, 0);
      cachedFrame.copyPixels(_drawTarget, _drawTarget.rect, new Point());
      _cachedFrames[i] = cachedFrame;
      
      // Apply disposal method for next frame
      if (i < _gif.frames.length - 1)
      {
        applyDisposalMethod(i);
      }
    }
    
    // Restore states
    _target = oldTarget;
    _prevFrame = oldPrevFrame;
    _allFramesCached = true;
  }
  
  /**
   * Sets the rendering target for subsequent render calls.
   * @param target The BitmapData to render onto
   */
  public function setTarget(target:BitmapData):Void
  {
    _target = target;
  }
  
  /**
   * Disposes all resources used by the GifRenderer.
   * Must be called when the renderer is no longer needed to prevent memory leaks.
   */
  public function dispose():Void
  {
    if (_restorer != null)
    {
      _restorer.dispose();
      _restorer = null;
    }
    if (_drawTarget != null)
    {
      _drawTarget.dispose();
      _drawTarget = null;
    }
    
    // Clear cached frames
    if (_cachedFrames != null)
    {
      for (i in 0..._cachedFrames.length)
      {
        if (_cachedFrames[i] != null)
        {
          _cachedFrames[i].dispose();
          _cachedFrames[i] = null;
        }
      }
      _cachedFrames = null;
    }
    
    _gif = null;
    _target = null;
  }
  
  /**
   * Renders a frame at the specified position on the target BitmapData.
   * Uses cached frames when available for optimal performance.
   * 
   * @param frame Index of the frame to render (0-based)
   * @param offsetX X position to render at on the target
   * @param offsetY Y position to render at on the target
   */
  public function render(frame:Int, offsetX:Int, offsetY:Int):Void
  {
    if (_gif == null || frame >= _gif.frames.length || frame < 0 || _target == null) return;
    
    // Use cached frame if available (fast path)
    if (_cachedFrames[frame] != null)
    {
      _tempPoint.x = offsetX;
      _tempPoint.y = offsetY;
      _target.copyPixels(_cachedFrames[frame], _cachedFrames[frame].rect, _tempPoint);
      _prevFrame = frame;
      return;
    }
    
    // Otherwise ensure frame is cached and render it
    ensureFrameCached(frame);
    if (_cachedFrames[frame] != null)
    {
      _tempPoint.x = offsetX;
      _tempPoint.y = offsetY;
      _target.copyPixels(_cachedFrames[frame], _cachedFrames[frame].rect, _tempPoint);
    }
  }
  
  /**
   * Ensures that a specific frame is cached, rendering it if necessary.
   * @param frame Index of the frame to cache
   */
  private function ensureFrameCached(frame:Int):Void
  {
    if (_cachedFrames[frame] != null) return;
    
    // Find the last cached frame before the requested one
    var startFrame:Int = 0;
    var i:Int = frame - 1;
    while (i >= 0)
    {
      if (_cachedFrames[i] != null)
      {
        startFrame = i + 1;
        break;
      }
      i--;
    }
    
    // Restore state from last cached frame
    if (startFrame > 0)
    {
      var lastCached:BitmapData = _cachedFrames[startFrame - 1];
      _drawTarget.copyPixels(lastCached, lastCached.rect, new Point());
      _prevFrame = startFrame - 1;
    }
    else
    {
      _drawTarget.fillRect(_drawTarget.rect, 0);
      _prevFrame = -1;
    }
    
    // Render all frames from startFrame to frame
    for (i in startFrame...frame + 1)
    {
      renderSingleFrame(i);
      
      // Create and store cache
      var cachedFrame:BitmapData = new BitmapData(_gif.width, _gif.height, true, 0);
      cachedFrame.copyPixels(_drawTarget, _drawTarget.rect, new Point());
      _cachedFrames[i] = cachedFrame;
      
      // Apply disposal method for next frame
      if (i < _gif.frames.length - 1)
      {
        applyDisposalMethod(i);
      }
    }
  }
  
  /**
   * Gets a cached frame. If not cached yet, it will be rendered and cached.
   * 
   * @param frame Index of the frame to retrieve
   * @return The cached BitmapData for the frame
   */
  public function getCachedFrame(frame:Int):BitmapData
  {
    if (frame < 0 || frame >= _cachedFrames.length) return null;
    
    if (_cachedFrames[frame] == null)
    {
      ensureFrameCached(frame);
    }
    
    return _cachedFrames[frame];
  }
  
  /**
   * Optimized rendering of a single GIF frame with proper disposal method handling.
   * 
   * @param frame Index of the frame to render
   */
  private function renderSingleFrame(frame:Int):Void
  {
    var gframe:GifFrame = _gif.frames[frame];
    
    // Save previous state if needed for RENDER_PREVIOUS disposal
    if (gframe.disposalMethod == DisposalMethod.RENDER_PREVIOUS)
    {
      if (_restorer != null) _restorer.dispose();
      _restorer = new BitmapData(gframe.width, gframe.height, true, 0);
      _tempRect.setTo(gframe.x, gframe.y, gframe.width, gframe.height);
      _restorer.copyPixels(_drawTarget, _tempRect, new Point());
    }
    
    // Copy frame with transparency support
    _tempPoint.setTo(gframe.x, gframe.y);
    _drawTarget.copyPixels(gframe.data, gframe.data.rect, _tempPoint, null, null, true);
    
    _prevFrame = frame;
  }
  
  /**
   * Applies the disposal method for a frame to prepare for the next frame.
   * @param frame Index of the frame whose disposal method should be applied
   */
  private function applyDisposalMethod(frame:Int):Void
  {
    var gframe:GifFrame = _gif.frames[frame];
    
    switch(gframe.disposalMethod)
    {
      case DisposalMethod.FILL_BACKGROUND:
        _tempRect.setTo(gframe.x, gframe.y, gframe.width, gframe.height);
        _drawTarget.fillRect(_tempRect, 0x00000000); // Transparent
        
      case DisposalMethod.RENDER_PREVIOUS:
        if (_restorer != null)
        {
          _tempPoint.setTo(gframe.x, gframe.y);
          _drawTarget.copyPixels(_restorer, _restorer.rect, _tempPoint);
          _restorer.dispose();
          _restorer = null;
        }
        
      default:
        // No action needed for NONE or NOT_DISPOSED
    }
  }
}
