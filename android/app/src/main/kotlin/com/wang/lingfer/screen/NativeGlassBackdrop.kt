package com.wang.lingfer.screen

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.RectF
import kotlin.math.min

/** A small owned crop of the existing clean frame; does not capture, request or persist images. */
internal object NativeGlassBackdrop {
    fun sample(source: Bitmap?, bounds: RectF): Bitmap? {
        if(source==null || source.isRecycled || bounds.width()<=0 || bounds.height()<=0) return null
        return try {
            val left=bounds.left.toInt().coerceIn(0,source.width-1)
            val top=bounds.top.toInt().coerceIn(0,source.height-1)
            val width=bounds.width().toInt().coerceIn(1,source.width-left)
            val height=bounds.height().toInt().coerceIn(1,source.height-top)
            val region=Bitmap.createBitmap(source,left,top,width,height)
            val scaled=Bitmap.createScaledBitmap(region,min(72,width),min(144,height),true)
            val output=scaled.copy(Bitmap.Config.ARGB_8888,true)
            if(scaled!==region && scaled!==source) scaled.recycle()
            if(region!==source) region.recycle()
            val pixels=IntArray(output.width*output.height)
            output.getPixels(pixels,0,output.width,0,0,output.width,output.height)
            repeat(3) {
                val input=pixels.clone()
                for(y in 0 until output.height) for(x in 0 until output.width) {
                    var red=0;var green=0;var blue=0;var count=0
                    for(dy in -2..2) for(dx in -2..2) {
                        val c=input[(y+dy).coerceIn(0,output.height-1)*output.width+(x+dx).coerceIn(0,output.width-1)]
                        red+=Color.red(c);green+=Color.green(c);blue+=Color.blue(c);count++
                    }
                    pixels[y*output.width+x]=Color.rgb(red/count,green/count,blue/count)
                }
            }
            output.setPixels(pixels,0,output.width,0,0,output.width,output.height)
            output
        } catch(_:Exception) { null }
    }
}
