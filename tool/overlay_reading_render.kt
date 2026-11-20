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
    ImageIO.write(longParagraph(), "png", File(out, "diagram-long-paragraph.png"))
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

/** Bands are a little stronger than the device tint so the per-line shape can be seen. */
private fun wash(g: Graphics2D, lines: List<Pair<Int, Int>>) {
    g.color = Color(236, 226, 206)
    lines.forEach { (top, width) -> g.fillRect(76, top, width, 36) }
}

private fun sheet(g: Graphics2D, left: Int, top: Int) {
    g.color = paper
    g.fillRoundRect(left, top, 340, 280, 18, 18)
    g.color = Color(228, 226, 220)
    g.stroke = BasicStroke(1f)
    g.drawRoundRect(left, top, 340, 280, 18, 18)
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 20)
    listOf("研究者认为，持续的练习", "比偶尔的努力更有效。", "熟悉的语境能让说法", "变得好记。").forEachIndexed { index, line ->
        g.drawString(line, left + 22, top + 48 + index * 36)
    }
    g.color = muted
    g.font = Font("Serif", Font.PLAIN, 13)
    g.drawString("Researchers maintain…", left + 22, top + 230)
    g.drawString("收起", left + 286, top + 230)
}

private fun asked(): BufferedImage {
    val (image, g) = base("Asked: a paper wash on the source, sheet beside it")
    val body = listOf(
        "Researchers maintain" to 180,
        "that consistent" to 228,
        "practice is more" to 276,
        "effective." to 324,
        "A familiar context" to 408,
        "can reveal a subtle" to 456,
        "distinction." to 504,
    )
    wash(g, listOf(168 to 250, 216 to 210, 264 to 230, 312 to 140))
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 26)
    body.forEach { (line, y) -> g.drawString(line, 80, y) }
    sheet(g, 500, 168)
    g.dispose()
    return image
}

private fun longParagraph(): BufferedImage {
    val (image, g) = base("Long paragraph: one wash band per line, not one block")
    val lines = listOf(
        "Researchers maintain that" to 160,
        "consistent practice is" to 214,
        "more effective than" to 268,
        "occasional effort." to 322,
    )
    wash(g, lines.map { (_, y) -> (y - 28) to 400 })
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 26)
    lines.forEach { (line, y) -> g.drawString(line, 80, y) }
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 26)
    g.drawString("The next paragraph stays clear.", 80, 430)
    sheet(g, 500, 160)
    g.dispose()
    return image
}
