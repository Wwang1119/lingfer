package com.wang.lingfer.screen

import java.awt.BasicStroke
import java.awt.Color
import java.awt.Font
import java.awt.Graphics2D
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO

/** Layout diagram of the overlay rules. Not a Fold5 photograph. */
fun main() {
    verifyOverlayReadingRules()
    val out = File(System.getenv("OVERLAY_RENDER_DIR") ?: "/tmp/lingfer-overlay")
    out.mkdirs()
    ImageIO.write(scene(before = true), "png", File(out, "overlay-before.png"))
    ImageIO.write(scene(before = false), "png", File(out, "overlay-after.png"))
    println(out.absolutePath)
}

private val paper = Color(250, 249, 244)
private val ink = Color(34, 40, 40)
private val muted = Color(102, 112, 115)
private val accent = Color(54, 95, 112)

private fun scene(before: Boolean): BufferedImage {
    val image = BufferedImage(880, 1120, BufferedImage.TYPE_INT_ARGB)
    val g = image.createGraphics()
    g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
    g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
    g.color = paper
    g.fillRect(0, 0, 880, 1120)
    g.color = muted
    g.font = Font("Serif", Font.PLAIN, 18)
    g.drawString(if (before) "Before  ·  full-height rails and a repeated 译" else "After  ·  short ticks, one ink, card follows the margin", 48, 56)
    val lines = listOf(
        "Researchers maintain that consistent" to 150,
        "practice is more effective than" to 198,
        "occasional effort." to 246,
        "A familiar context can reveal a" to 330,
        "subtle distinction and make an" to 378,
        "unfamiliar expression easier to" to 426,
        "remember." to 474,
    )
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 28)
    val body = if (before) lines else listOf(
        "Researchers maintain" to 150,
        "that consistent" to 198,
        "practice is more" to 246,
        "effective." to 294,
        "A familiar context" to 378,
        "can reveal a subtle" to 426,
        "distinction." to 474,
    )
    body.forEach { (line, y) -> g.drawString(line, 120, y) }
    if (before) drawBefore(g) else drawAfter(g)
    g.dispose()
    return image
}

private fun drawBefore(g: Graphics2D) {
    g.color = Color(78, 109, 97, 180)
    g.stroke = BasicStroke(3f)
    g.drawLine(78, 120, 78, 520)
    g.font = Font("Serif", Font.BOLD, 16)
    var y = 140
    while (y < 500) {
        g.drawString("译", 68, y)
        y += 36
    }
    g.color = Color(142, 103, 54)
    g.stroke = BasicStroke(2f)
    g.drawLine(120, 158, 430, 158)
    g.color = Color(250, 239, 215)
    g.fillRoundRect(150, 250, 520, 150, 16, 16)
    g.color = Color(83, 54, 28)
    g.font = Font("SansSerif", Font.PLAIN, 16)
    g.drawString("维持", 168, 290)
    g.color = Color(54, 95, 112)
    g.font = Font("SansSerif", Font.BOLD, 18)
    g.drawString("收起", 580, 280)
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 18)
    g.drawString("译文盖住了正在读的这一段。", 168, 340)
}

private fun drawAfter(g: Graphics2D) {
    g.color = Color(54, 95, 112, 140)
    g.stroke = BasicStroke(1.6f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
    g.drawLine(86, 214, 86, 232)
    g.drawLine(86, 430, 86, 448)
    g.color = accent
    g.stroke = BasicStroke(1.4f)
    g.drawLine(120, 252, 430, 252)
    g.color = paper
    g.fillRoundRect(470, 150, 340, 280, 22, 22)
    g.color = Color(228, 226, 220)
    g.drawRoundRect(470, 150, 340, 280, 22, 22)
    g.color = muted
    g.font = Font("Serif", Font.PLAIN, 13)
    g.drawString("原  文", 494, 186)
    g.drawString("收起", 740, 186)
    g.font = Font("Serif", Font.PLAIN, 16)
    g.drawString("Researchers maintain that", 494, 220)
    g.color = ink
    g.font = Font("Serif", Font.PLAIN, 20)
    val translation = listOf("研究者认为，持续的练习", "比偶尔的努力更有效。", "熟悉的语境能让一个", "生疏的说法变得好记。")
    translation.forEachIndexed { index, line -> g.drawString(line, 494, 268 + index * 34) }
}
