package com.wang.lingfer.screen

import java.awt.BasicStroke
import java.awt.Color
import java.awt.Font
import java.awt.Graphics2D
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO

/**
 * Layout diagrams of the overlay rules.
 * These are not photographs and not Fold5 visual acceptance.
 */
fun main() {
    verifyOverlayReadingRules()
    val out = File(System.getenv("OVERLAY_RENDER_DIR") ?: "/tmp/lingfer-overlay")
    out.mkdirs()
    ImageIO.write(resting(dense = false), "png", File(out, "diagram-resting.png"))
    ImageIO.write(resting(dense = true), "png", File(out, "diagram-dense-resting.png"))
    ImageIO.write(asked(), "png", File(out, "diagram-asked.png"))
    println(out.absolutePath)
}

private val paper = Color(250, 249, 244)
private val ink = Color(34, 40, 40)
private val muted = Color(102, 112, 115)

private fun base(title: String): Pair<BufferedImage, Graphics2D> {
    val image = BufferedImage(880, 1120, BufferedImage.TYPE_INT_ARGB)
    val g = image.createGraphics()
    g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
    g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
    g.color = paper
    g.fillRect(0, 0, 880, 1120)
    g.color = muted
    g.font = Font("Serif", Font.PLAIN, 16)
    g.drawString(title, 48, 48)
    g.drawString("Diagram only. Not a device photo.", 48, 72)
    return image to g
}

private fun resting(dense: Boolean): BufferedImage {
    val (image, g) = base(
        if (dense) "Dense page at rest: no ticks, no 译, no chips"
        else "Resting page: the document is left alone",
    )
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, if (dense) 22 else 28)
    val lines = if (dense) {
        (0 until 18).map { "Line ${it + 1}. A short paragraph on a crowded page." to 120 + it * 48 }
    } else {
        listOf(
            "Researchers maintain that" to 180,
            "consistent practice is more" to 228,
            "effective than occasional effort." to 276,
            "A familiar context can reveal" to 360,
            "a subtle distinction." to 408,
        )
    }
    lines.forEach { (line, y) -> g.drawString(line, 96, y) }
    g.dispose()
    return image
}

private fun asked(): BufferedImage {
    val (image, g) = base("After the reader asks: translation first, one sheet")
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 26)
    listOf(
        "Researchers maintain" to 180,
        "that consistent" to 226,
        "practice is more" to 272,
        "effective." to 318,
        "A familiar context" to 400,
        "can reveal a subtle" to 446,
        "distinction." to 492,
    ).forEach { (line, y) -> g.drawString(line, 72, y) }
    g.color = paper
    g.fillRoundRect(430, 160, 390, 300, 22, 22)
    g.color = Color(228, 226, 220)
    g.stroke = BasicStroke(1f)
    g.drawRoundRect(430, 160, 390, 300, 22, 22)
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 22)
    listOf(
        "研究者认为，持续的练习" to 210,
        "比偶尔的努力更有效。" to 248,
        "熟悉的语境能让一个" to 286,
        "生疏的说法变得好记。" to 324,
    ).forEach { (line, y) -> g.drawString(line, 454, y) }
    g.color = muted
    g.font = Font("Serif", Font.PLAIN, 14)
    g.drawString("Researchers maintain that…", 454, 420)
    g.drawString("收起", 760, 420)
    g.dispose()
    return image
}
