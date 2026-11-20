package com.wang.lingfer.screen

import android.app.*
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.*
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.Log
import android.view.*
import android.widget.*
import com.wang.lingfer.MainActivity
import org.json.JSONArray
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.min

/** User-authorized read-only session. Screen coordinates stay local. */
class ScreenReaderService : Service(), SharedPreferences.OnSharedPreferenceChangeListener {
    companion object {
        const val START = "lingfer.screen.START"
        const val CAPTURE = "lingfer.screen.CAPTURE"
        const val STOP = "lingfer.screen.STOP"
        const val HOST = "lingfer.screen.HOST"
        const val PAUSE = "lingfer.screen.PAUSE"
        private const val CHANNEL = "lingfer_screen_reading"
        private const val NOTIFICATION_ID = 7401
    }
    private val main = Handler(Looper.getMainLooper())
    private val framesThread = HandlerThread("lingfer-frames").apply { start() }
    private val frames = Handler(framesThread.looper)
    private val network = Executors.newFixedThreadPool(2)
    private val ocr = NativeOcrEngine()
    private val prefs by lazy { getSharedPreferences("lingfer_screen", MODE_PRIVATE) }
    private val aiConsentPrefs by lazy { NativeAiConsent.preferences(this) }
    private fun aiAllowed() = NativeAiConsent.isAllowed(aiConsentPrefs)
    private val windows by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }
    private val lexicon by lazy { OfflineVocabulary(this) }
    private val translatorHolder = lazy { MultilingualTranslator(prefs, lexicon, ::aiAllowed) }
    private val translator get() = translatorHolder.value
    private val annotations by lazy { GlassAnnotations(this, windows, ::showDetail) }
    private val paragraphAnnotations by lazy {
        ParagraphAnnotations(this, windows, ::updateMasks, ::recoverParagraphTranslation, ::onParagraphWindowChange)
    }
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var bubble: TextView? = null
    private var panel: View? = null
    @Volatile private var stopping = false
    @Volatile private var paused = false
    @Volatile private var capturedContentVisible = true
    @Volatile private var detailOpen = false
    @Volatile private var busy = false
    @Volatile private var translationFailed = false
    private val revision = AtomicInteger(0)
    private data class CaptureMasks(val all: List<RectF>, val persistent: List<RectF>, val card: RectF?)
    @Volatile private var masks = CaptureMasks(emptyList(), emptyList(), null)
    private val windowRevision = AtomicInteger()
    @Volatile private var changingOwnWindows = false
    private val cleanFence = AtomicInteger()
    private var fallbackAllowedAt = 0L
    private var beforeHideMasks: List<RectF> = emptyList()
    private var lastScanHadCard = false
    private var screenMasks: List<RectF> = emptyList()
    private var captureArea = Rect()
    @Volatile private var lastMotionAt = 0L
    @Volatile private var suppressFramesUntil = 0L
    private var lastSampleAt = 0L
    private var lastScanAt = 0L
    private var fingerprint: IntArray? = null
    private var candidate: Bitmap? = null
    private var lastClean: Bitmap? = null
    private var scanScheduled = false
    @Volatile private var awaitingClean = false
    private var cleanFrameReady = false
    @Volatile private var overlaysHidden = true
    private var candidateMasks: List<RectF> = emptyList()
    private var candidateHasCard = false
    @Volatile private var dirty = false
    @Volatile private var activeKey = ""
    private var currentPage: OcrPage? = null
    private var acceptedRevision = -1
    private var currentPageParts:List<PageParagraph> = emptyList()
    private var pageTranslationError:String?=null
    private var pageTranslationLoading=false
    private val previewRevision = AtomicInteger()
    private var refreshPreview: (() -> Unit)? = null
    private var readingError:String?=null
    private var openTranslationWhenReady=false
    private var currentHits: List<WordHit> = emptyList()
    private val explanationCache = android.util.LruCache<String, String>(80)
    private val pendingExplanations=mutableSetOf<String>()
    private var detailExplanationKey=""

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() { stopSelf() }
        override fun onCapturedContentResize(width: Int, height: Int) {
            if (width > 0 && height > 0 && display != null) resizeCapture(width, height)
        }
        override fun onCapturedContentVisibilityChanged(isVisible: Boolean) {
            if (capturedContentVisible == isVisible || stopping) return
            capturedContentVisible = isVisible
            if (isVisible) {
                forceCapture()
            } else {
                revision.incrementAndGet()
                cancelPageBatch()
                clearAnnotations()
                removePanel()
            }
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            STOP -> stopSelf()
            CAPTURE -> forceCapture()
            PAUSE -> setPaused(intent.getBooleanExtra("paused", !paused))
            HOST -> {
                if (ScreenReaderState.hostActive) removePanel()
                if (prefs.getBoolean("automatic", true)) invalidatePage()
                else {
                    revision.incrementAndGet()
                    cancelPageBatch()
                    clearAnnotations()
                    frames.post { fingerprint = null; dirty = false }
                }
            }
            START -> {
                if (projection != null) return START_NOT_STICKY
                try {
                    startNotification()
                    @Suppress("DEPRECATION")
                    val data = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra("projectionData", Intent::class.java)
                        else intent.getParcelableExtra<Intent>("projectionData")
                    if (data == null) { stopSelf(); return START_NOT_STICKY }
                    val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    projection = manager.getMediaProjection(intent.getIntExtra("resultCode", Activity.RESULT_CANCELED), data)
                    projection!!.registerCallback(projectionCallback, main)
                    val metrics = resources.displayMetrics
                    val fullScreen = fullDisplayBounds()
                    captureArea = fullScreen
                    reader = makeReader(fullScreen.width(), fullScreen.height())
                    display = projection!!.createVirtualDisplay("语渡实时阅读", fullScreen.width(), fullScreen.height(),
                        metrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader!!.surface, null, main)
                    prefs.registerOnSharedPreferenceChangeListener(this)
                    aiConsentPrefs.registerOnSharedPreferenceChangeListener(this)
                    ScreenReaderState.running = true; ScreenReaderState.paused = false
                    showBubble(); emitStatus()
                } catch (error: Exception) { Log.w("LingferScreen", "Could not start authorized session", error); fail("读屏未能开启，请回到语渡重新授权。"); stopSelf() }
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION") private fun startNotification() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "实时阅读", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, ScreenReaderService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_menu_view).setContentTitle("语渡实时阅读已开启")
            .setContentText("页面变化后自动更新 · 点悬浮按钮打开菜单 · 长按停止").setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "停止阅读", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(NOTIFICATION_ID, notification)
    }

    private fun makeReader(width: Int, height: Int) = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 3).also { source ->
        source.setOnImageAvailableListener({ incoming ->
            val image = try { incoming.acquireLatestImage() } catch (_: Exception) { null }
            if (image != null) try { acceptFrame(image) } catch (error: Exception) { Log.w("LingferScreen", "Frame unavailable", error) } finally { image.close() }
        }, frames)
    }

    private fun acceptFrame(image: Image) {
        val automatic = prefs.getBoolean("automatic", true)
        if (stopping || paused || detailOpen || !capturedContentVisible || ScreenReaderState.hostActive || (!automatic && !dirty)) return
        val now = SystemClock.elapsedRealtime()
        val drawRevision = windowRevision.get()
        if (changingOwnWindows || now < suppressFramesUntil) return
        if (now-lastSampleAt < 180 && !awaitingClean && !dirty) return
        lastSampleAt = now
        val frameMasks = masks
        val signature = sample(image, frameMasks.all)
        if (drawRevision != windowRevision.get() || changingOwnWindows) return
        val previous = fingerprint
        val changed = previous == null || distance(previous, signature) > .003f
        fingerprint = signature
        if (changed) {
            dirty = true
            lastMotionAt = now
            revision.incrementAndGet()
        }
        if (awaitingClean && !cleanFrameReady) {
            // Single-app capture can stay completely still when our windows hide.
            // Its fallback carries all the masks from before hide, including the rail.
            if (changed || candidate == null) {
                retainFrame(image, (beforeHideMasks + frameMasks.all).distinct(), frameMasks.card != null)
            }
            return
        }
        if (changed && !overlaysHidden) {
            awaitingClean = true
            cleanFrameReady = false
            val fence = cleanFence.incrementAndGet()
            beforeHideMasks = frameMasks.all
            retainFrame(image, frameMasks.all, frameMasks.card != null)
            main.post {
                if (stopping || fence != cleanFence.get()) return@post
                cancelPageBatch()
                annotations.hide()
                // Rails can leave so the next frame is clean. The open translation card stays.
                paragraphAnnotations.hide()
                overlaysHidden = true
                requestCleanFrame(fence)
            }
            scheduleScan()
            return
        }
        if (changed || awaitingClean || (dirty && candidate == null)) {
            retainFrame(image, if (overlaysHidden) frameMasks.persistent else frameMasks.all, frameMasks.card != null)
            awaitingClean = false
            cleanFrameReady = false
            scheduleScan()
        }
    }

    // Called on main only after all affected WindowManager operations return.
    // If the capture contains those windows, this pulse supplies a fresh compositor frame.
    private fun requestCleanFrame(fence: Int) {
        main.postDelayed({
            if (stopping || fence != cleanFence.get()) return@postDelayed
            frames.post {
                if (fence == cleanFence.get()) {
                    cleanFrameReady = true
                    fallbackAllowedAt = SystemClock.elapsedRealtime() + 400
                }
            }
            pulseCompositor.run()
            // App-only sharing does not composite our orb. Reattach the output
            // of this same authorized virtual display once if it sent no clean
            // frame; the reader can then render the stationary PDF again.
            frames.postDelayed({
                if (!stopping && awaitingClean && cleanFence.get() == fence) main.post {
                    val surface = reader?.surface
                    val activeDisplay = display
                    if (!stopping && !paused && !detailOpen && capturedContentVisible && !ScreenReaderState.hostActive &&
                        awaitingClean && fence == cleanFence.get() && activeDisplay != null && surface != null) {
                        try {
                            activeDisplay.surface = null
                            activeDisplay.surface = surface
                        } catch (error: RuntimeException) {
                            Log.d("LingferScreen", "Capture surface refresh unavailable", error)
                        }
                    }
                }
            }, 190)
        }, 240)
    }

    private val pulseCompositor = Runnable {
        if (!stopping && !paused) {
            bubble?.alpha = .96f
            main.postDelayed({ bubble?.alpha = 1f }, 64)
        }
    }

    private fun retainFrame(image: Image, excluded: List<RectF>, hasCard: Boolean) {
        val next = bitmap(image)
        candidate?.takeUnless { it === lastClean || it.isRecycled }?.recycle()
        candidate = next
        candidateMasks = excluded
        candidateHasCard = hasCard
    }

    private fun scheduleScan() {
        if (scanScheduled || stopping) return
        scanScheduled = true
        frames.postDelayed({
            scanScheduled = false
            if (stopping || paused || detailOpen || !capturedContentVisible || ScreenReaderState.hostActive || !dirty) return@postDelayed
            val now = SystemClock.elapsedRealtime()
            if (busy || changingOwnWindows || now < suppressFramesUntil || (awaitingClean && (!cleanFrameReady || now < fallbackAllowedAt)) || now-lastMotionAt < 240 || now-lastScanAt < 650) { scheduleScan(); return@postDelayed }
            val bitmap = candidate ?: return@postDelayed
            candidate = null; busy = true; dirty = false; awaitingClean = false; lastScanAt = now
            val token = revision.get()
            val options = ReadingOptions.load(prefs)
            // Any frame captured before hide completion cannot contribute text
            // from our own labels. Their rectangles are known locally.
            val topBand = chromeTop(bitmap.height)
            val bottomBand = chromeBottom(bitmap.height)
            val excluded = candidateMasks + listOf(
                RectF(0f, 0f, bitmap.width.toFloat(), topBand),
                RectF(0f, bitmap.height - bottomBand, bitmap.width.toFloat(), bitmap.height.toFloat()),
            )
            val hadCard = candidateHasCard
            val input = NativeOcrEngine.maskOverlayPixels(bitmap, excluded)
            if (input !== bitmap) bitmap.recycle()
            main.post {
                if (stopping) { input.recycle(); busy = false; return@post }
                ocr.recognize(input, options.source, excluded, screenChrome = true) { page, error ->
                    busy = false
                    if (stopping || token != revision.get() || paused || detailOpen || !capturedContentVisible || ScreenReaderState.hostActive) { input.recycle(); return@recognize }
                    if (page == null) { input.recycle(); fail("文字暂未读清，停稳页面后会自动重试。"); return@recognize }
                    lastClean?.takeUnless { it === input || it.isRecycled }?.recycle(); lastClean = input
                    lastScanHadCard = hadCard
                    if (hadCard && paragraphAnnotations.persistentRegion == null) {
                        invalidatePage()
                        return@recognize
                    }
                    processPage(page, options, token, now)
                }
            }
        }, 280)
    }

    private fun processPage(page: OcrPage, options: ReadingOptions, token: Int, startedAt: Long) {
        currentPage = page
        acceptedRevision = token
        prefs.edit().putString("lastText", page.text).apply()
        val key = MessageDigest.getInstance("SHA-256").digest((options.signature+"|"+page.language+"|"+page.text).toByteArray()).joinToString("") { "%02x".format(it) }
        if (options.mode == "translation") {
            beginPageTranslation(page, options, key, token)
            return
        }
        if (key == activeKey) {
            showAnnotations(page, currentHits); return
        }
        if (translatorHolder.isInitialized()) translator.cancelBatch()
        activeKey = key; currentHits = emptyList()
        translationFailed = false;readingError=null
        bubble?.text = "…";bubble?.textSize=20f
        network.execute {
            if (key != activeKey || stopping) return@execute
            try {
                val hits = translator.analyze(page, options, prefs.getStringSet("known", emptySet()) ?: emptySet())
                main.post {
                    if (stopping || key != activeKey || paused || ScreenReaderState.hostActive) return@post
                    currentHits = hits
                    if (dirty || busy || awaitingClean) return@post
                    bubble?.text = "渡";bubble?.textSize=20f;readingError=null
                    val latest = currentPage ?: page
                    showAnnotations(latest, hits)
                    val duration = SystemClock.elapsedRealtime()-startedAt
                    prefs.edit().putString("lastHits", JSONArray(hits.map { it.json() }).toString()).putString("lastOptionsSignature", options.signature).putString("lastDetectedLanguage", latest.language).apply()
                    ScreenReaderState.emit(mapOf("kind" to "capture", "text" to latest.text, "hits" to hits.map { it.nativeMap() }, "durationMs" to duration, "detectedLanguage" to latest.language))
                    Log.d("LingferScreen", "Live ${options.source}->${options.target}: ${hits.size} aligned words in ${duration}ms")
                }
            } catch (failure: Exception) { main.post {
                if (!stopping && key == activeKey && (failure is AiConsentRequired || !aiAllowed())) {
                    readingError = NativeAiConsent.prompt
                    bubble?.text = "渡"
                    ScreenReaderState.emit(mapOf("kind" to "error", "message" to readingError))
                    return@post
                }
                if (!stopping && key == activeKey) { currentHits = emptyList(); translationFailed = true; bubble?.text = "重试";bubble?.textSize=14f; fail("当前语言方向暂未完成翻译，点悬浮按钮打开菜单重试。英语→中文基础释义可离线使用。") }
            } }
        }
    }

    private fun showAnnotations(page: OcrPage, hits: List<WordHit>) {
        if (ReadingOptions.load(prefs).mode == "translation") {
            showParagraphAnnotations()
            return
        }

        if (stopping || paused || detailOpen || !capturedContentVisible || ScreenReaderState.hostActive) return
        suppressFramesUntil = SystemClock.elapsedRealtime() + 240
        annotations.show(page, hits, lastClean, screenMasks.takeLast(1), captureArea)
        overlaysHidden = annotations.regions.isEmpty()
        updateMasks()
        main.postDelayed({
            if (!stopping && !paused && !ScreenReaderState.hostActive) { bubble?.alpha = .98f; main.postDelayed({ bubble?.alpha = 1f }, 80) }
        }, 260)
    }

    private fun beginPageTranslation(page: OcrPage, options: ReadingOptions, key: String, token: Int, retry: Boolean = false) {
        val originals = page.readingParagraphs
        val sameParagraphs = key == activeKey && originals.size == currentPageParts.size &&
            originals.indices.all { i -> originals[i].id == currentPageParts[i].id && originals[i].source == currentPageParts[i].source }
        if (sameParagraphs && !pageTranslationLoading && !retry) {
            showParagraphAnnotations()
            return
        }
        cancelPageBatch()
        activeKey = key
        currentHits = emptyList()
        val remembered = currentPageParts.mapNotNull { part ->
            part.translation?.takeIf { it.isNotBlank() }?.let { part.source to it }
        }.toMap()
        // A scroll assigns new line ids. Keep a finished translation for the same source
        // so the open card is not replaced by an empty "正在翻译".
        currentPageParts = if (sameParagraphs) currentPageParts else originals.map { part ->
            remembered[part.source]?.let { part.copy(translation = it) } ?: part
        }
        val source = if (options.source == "auto") page.language else options.source
        pageTranslationError = when {
            originals.isEmpty() -> null
            source == options.target -> "原文和译文设为了相同语言（${ReadingOptions.languages[source] ?: source}）。"
            !aiAllowed() -> NativeAiConsent.prompt
            else -> null
        }
        pageTranslationLoading = originals.isNotEmpty() && pageTranslationError == null
        readingError = pageTranslationError
        prefs.edit().putString("lastHits", "[]").putString("lastOptionsSignature", options.signature).apply()
        val requestedAt = SystemClock.elapsedRealtime()
        Log.d("LingferScreen", "Page ${token}: prefetch ${originals.size} visible paragraphs")
        bubble?.text = when {
            pageTranslationLoading -> "…"
            source == options.target && originals.isNotEmpty() -> "语言"
            else -> "渡"
        }
        bubble?.textSize = if (bubble?.text == "语言") 14f else 20f
        emitPageTranslation()
        if (originals.isEmpty() || source == options.target) return

        fun isCurrent() = !stopping && !paused && capturedContentVisible && !ScreenReaderState.hostActive &&
            token == revision.get() && key == activeKey
        network.execute {
            if (!isCurrent()) return@execute
            var result = originals
            val failure = try {
                result = translator.translateParagraphs(originals, page.language, options, ::isCurrent) { snapshot ->
                    result = snapshot
                    main.post {
                        if (isCurrent() && currentPageParts != snapshot) {
                            currentPageParts = snapshot
                            emitPageTranslation()
                        }
                    }
                }
                null
            } catch (_: AiConsentRequired) {
                NativeAiConsent.prompt
            } catch (error: Exception) {
                if (error.message?.contains("12000") == true) error.message
                else "翻译暂未完成，可以重试。"
            }
            main.post {
                if (!isCurrent()) return@post
                currentPageParts = result
                pageTranslationLoading = false
                pageTranslationError = failure
                readingError = failure
                bubble?.text = if (failure == null || failure == NativeAiConsent.prompt) "渡" else "重试"
                bubble?.textSize = if (bubble?.text == "重试") 14f else 20f
                val elapsed = SystemClock.elapsedRealtime() - requestedAt
                Log.d("LingferScreen", "Page ${token}: ready ${result.count { it.translation != null }}/${result.size} in ${elapsed}ms")
                emitPageTranslation()
                if (openTranslationWhenReady && !detailOpen) {
                    openTranslationWhenReady = false
                    showPageTranslation()
                }
            }
        }
    }

    private fun showParagraphAnnotations() {
        val page = currentPage ?: return
        if (stopping || paused || detailOpen || !capturedContentVisible || ScreenReaderState.hostActive ||
            acceptedRevision != revision.get() || captureArea.isEmpty || dirty || awaitingClean) return
        paragraphAnnotations.show(page, currentPageParts, pageTranslationLoading, pageTranslationError,
            captureArea, screenMasks.takeLast(1))
        overlaysHidden = paragraphAnnotations.regions.isEmpty()
    }

    private fun onParagraphWindowChange(started: Boolean) {
        if (started) {
            changingOwnWindows = true
            windowRevision.incrementAndGet()
            return
        }
        updateMasks()
        suppressFramesUntil = SystemClock.elapsedRealtime() + 180
        windowRevision.incrementAndGet()
        changingOwnWindows = false
        main.removeCallbacks(pulseCompositor)
        main.postDelayed(pulseCompositor, 200)
        // A new page read while a card covers it has intentionally omitted those
        // pixels. Closing the card reveals fresh source, even if the PDF is static.
        if (lastScanHadCard && paragraphAnnotations.persistentRegion == null && !stopping && !detailOpen &&
            !ScreenReaderState.hostActive && !paused && !dirty && capturedContentVisible) {
            lastScanHadCard = false
            main.post { if (!dirty && paragraphAnnotations.persistentRegion == null && !stopping) invalidatePage() }
        }
    }

    private fun recoverParagraphTranslation() {
        val error = pageTranslationError
        when {
            error == NativeAiConsent.prompt -> startActivity(Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
            error?.contains("相同语言") == true -> {
                val target = if (ReadingOptions.load(prefs).target == "zh") "en" else "zh"
                prefs.edit().putString("targetLanguage", target).apply()
                ScreenReaderState.emit(mapOf("kind" to "changed"))
            }
            else -> {
                val page = currentPage ?: return
                if (acceptedRevision == revision.get()) {
                    beginPageTranslation(page, ReadingOptions.load(prefs), activeKey, acceptedRevision, retry = true)
                }
            }
        }
    }

    private fun clearAnnotations() {
        annotations.clear()
        paragraphAnnotations.clear()
        overlaysHidden = true
        updateMasks()
    }

    private fun cancelPageBatch() {
        if (translatorHolder.isInitialized() && pageTranslationLoading) translator.cancelBatch()
    }

    private fun forceCapture() { activeKey = ""; invalidatePage() }
    private fun invalidatePage() {
        revision.incrementAndGet()
        cancelPageBatch()
        lastScanHadCard = false
        val fence = cleanFence.incrementAndGet()
        val beforeClear = masks.all
        clearAnnotations()
        frames.post {
            beforeHideMasks = beforeClear
            fingerprint = null; dirty = true; awaitingClean = true; cleanFrameReady = false
            candidate?.takeUnless { it === lastClean || it.isRecycled }?.recycle(); candidate = null
            scheduleScan()
        }
        requestCleanFrame(fence)
    }
    private fun setPaused(value: Boolean) {
        paused = value; ScreenReaderState.paused = value
        if (value) {
            revision.incrementAndGet()
            cancelPageBatch()
            clearAnnotations()
            bubble?.text = "Ⅱ"
        } else { bubble?.text = "渡"; forceCapture() }
        emitStatus()
    }
    private fun emitStatus() = ScreenReaderState.emit(mapOf("kind" to "status", "running" to !stopping, "paused" to paused))

    override fun onSharedPreferenceChanged(preferences: SharedPreferences?, key: String?) {
        if (preferences === aiConsentPrefs) {
            if (key != null && key != NativeAiConsent.versionKey && key != NativeAiConsent.allowedKey) return
            if (!aiAllowed()) {
                if (translatorHolder.isInitialized()) translator.close()
                (panel as? NativeReadingPanel)?.showOffline(explanationCache.get(detailExplanationKey))
                if (readingError != null) readingError = NativeAiConsent.prompt
                if (pageTranslationLoading || pageTranslationError != null) {
                    pageTranslationLoading = false
                    pageTranslationError = NativeAiConsent.prompt
                    readingError = pageTranslationError
                    emitPageTranslation()
                }
            } else {
                (panel as? NativeReadingPanel)?.enableExplanation(explanationCache.get(detailExplanationKey))
                if (readingError == NativeAiConsent.prompt) readingError = null
                if (pageTranslationError == NativeAiConsent.prompt) {
                    pageTranslationError = null
                    emitPageTranslation()
                }
            }
            refreshPreview?.invoke()
            if (panel is NativeReadingMenu) showMenu()
            forceCapture()
            return
        }
        if (key == "automatic" && !prefs.getBoolean("automatic", true)) { paused = false; ScreenReaderState.paused = false; bubble?.text = "渡" }
        if (key in setOf("sourceLanguage", "targetLanguage", "level", "generalDifficulty", "automatic", "known", "readingMode")) {
            activeKey = ""; invalidatePage()
        }
    }

    private fun resizeCapture(width: Int, height: Int) {
        if (stopping) return
        val metrics = resources.displayMetrics
        val available = Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
        val nextArea = AnnotationGeometry.viewport(windows, width, height, available, fullDisplayBounds()) ?: Rect()
        val relocated = captureArea != nextArea
        captureArea = nextArea
        if (reader?.width == width && reader?.height == height) {
            if (relocated) forceCapture()
            return
        }
        try {
            val old = reader; val next = makeReader(width, height)
            display?.resize(width, height, resources.displayMetrics.densityDpi); display?.surface = next.surface; reader = next; old?.close()
            removePanel(); fitBubble(); forceCapture()
        } catch (_: Exception) { fail("画面尺寸已变化，请重新开启阅读。"); stopSelf() }
    }
    override fun onConfigurationChanged(config: Configuration) {
        super.onConfigurationChanged(config); removePanel(); annotations.clear(); fitBubble(); forceCapture()
        if (Build.VERSION.SDK_INT < 34) {
            val bounds = fullDisplayBounds()
            resizeCapture(bounds.width(), bounds.height())
        } else {
            reader?.let { resizeCapture(it.width, it.height) }
        }
    }

    private fun fullDisplayBounds(): Rect {
        val metrics = resources.displayMetrics
        return AnnotationGeometry.displayBounds(windows, Rect(0, 0, metrics.widthPixels, metrics.heightPixels))
    }

    private fun showBubble() {
        if (bubble != null) return
        val view = NativeFloatingOrb(this).apply {
            text = "渡"; elevation = 0f
            contentDescription = "语渡实时阅读：点击打开菜单，长按停止"
        }
        val params = GlassAnnotations.overlayParams(dp(48), dp(48)).apply { gravity = Gravity.TOP or Gravity.RIGHT; x = dp(12); y = dp(140) }
        var initialX = 0; var initialY = 0; var downX = 0f; var downY = 0f; var moved = false; var downTime = 0L
        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> { initialX=params.x; initialY=params.y; downX=event.rawX; downY=event.rawY; moved=false; downTime=event.eventTime }
                MotionEvent.ACTION_MOVE -> {
                    if (abs(event.rawX-downX)+abs(event.rawY-downY)>dp(8)) moved=true
                    if (moved) { params.x=(initialX-(event.rawX-downX).toInt()).coerceIn(0, (resources.displayMetrics.widthPixels-dp(48)).coerceAtLeast(0)); params.y=(initialY+(event.rawY-downY).toInt()).coerceIn(dp(24), (resources.displayMetrics.heightPixels-dp(90)).coerceAtLeast(dp(24))); windows.updateViewLayout(view, params); updateMasks() }
                }
                MotionEvent.ACTION_UP -> if (!moved) { if (event.eventTime-downTime >= ViewConfiguration.getLongPressTimeout()) view.performLongClick() else view.performClick() }
            }; true
        }
        view.setOnClickListener { if (panel != null) dismissPanel() else showMenu() }
        view.setOnLongClickListener { stopSelf(); true }
        windows.addView(view, params); bubble=view; view.post { updateMasks() }
    }
    private fun fitBubble() {
        val view=bubble ?: return; val params=view.layoutParams as WindowManager.LayoutParams
        params.x=params.x.coerceIn(0, (resources.displayMetrics.widthPixels-dp(48)).coerceAtLeast(0)); params.y=params.y.coerceIn(dp(24), (resources.displayMetrics.heightPixels-dp(90)).coerceAtLeast(dp(24)))
        try { windows.updateViewLayout(view, params) } catch (_: Exception) {}; updateMasks()
    }
    private fun updateMasks() {
        val padding = dp(8).toFloat()
        fun padded(rect: RectF) = RectF(rect).apply { inset(-padding, -padding) }
        val own = (annotations.regions + paragraphAnnotations.regions).map(::padded)
        val orb = bubble?.let { view ->
            val xy = IntArray(2)
            view.getLocationOnScreen(xy)
            RectF(xy[0].toFloat(), xy[1].toFloat(), xy[0] + view.width.toFloat(), xy[1] + view.height.toFloat())
                .takeUnless { it.isEmpty }?.let(::padded)
        }
        screenMasks = own + listOfNotNull(orb)
        val source = reader
        masks = if (source == null || captureArea.isEmpty) CaptureMasks(emptyList(), emptyList(), null) else {
            val coordinates = AnnotationCoordinates(source.width, source.height, captureArea)
            val card = paragraphAnnotations.persistentRegion?.let(::padded)?.let(coordinates::toCapture)
            CaptureMasks(screenMasks.map(coordinates::toCapture), listOfNotNull(card, orb?.let(coordinates::toCapture)), card)
        }
    }

    private fun showDetail(hit: WordHit) {
        removePanel(); detailOpen=true; clearAnnotations()
        val page = currentPage
        val translateParagraph = page?.let { sourcePage ->
            sourcePage.paragraphFor(hit)?.let { paragraph ->
                { showTranslationPreview(listOf(paragraph), sourcePage.language) }
            }
        }
        val scope = ReadingOptions.load(prefs).learningScope(page?.language)
        lateinit var readingPanel: NativeReadingPanel
        val explanationKey="${hit.sourceLanguage}|${hit.targetLanguage}|${hit.word}|${hit.context}"
        detailExplanationKey=explanationKey
        fun loadExplanation(retry: Boolean = false) {
            if (!aiAllowed()) {
                readingPanel.showOffline(explanationCache.get(explanationKey))
                return
            }
            if (!retry) explanationCache.get(explanationKey)?.let { readingPanel.showAnswer(it); return }
            readingPanel.showLoading()
            if(!pendingExplanations.add(explanationKey)) return
            network.execute {
                val response = try {
                    translator.explain(hit, ReadingOptions.load(prefs))
                } catch (_: AiConsentRequired) {
                    null
                } catch (_: Exception) {
                    "详解暂未响应，原词译义和收藏仍可使用。"
                }
                main.post {
                    pendingExplanations.remove(explanationKey)
                    if (!aiAllowed() || response == null) {
                        if (!stopping && detailExplanationKey == explanationKey) {
                            (panel as? NativeReadingPanel)?.showOffline(explanationCache.get(explanationKey))
                            if (aiAllowed()) (panel as? NativeReadingPanel)?.enableExplanation(explanationCache.get(explanationKey))
                        }
                        return@post
                    }
                    if (response != "详解暂未响应，原词译义和收藏仍可使用。") explanationCache.put(explanationKey,response)
                    if (!stopping && detailExplanationKey==explanationKey) (panel as? NativeReadingPanel)?.showAnswer(response)
                }
            }
        }
        readingPanel=NativeReadingPanel(this,hit,scope.value,scope.title,scope.choices,currentHits,prefs.getString("saved","[]") ?: "[]",
            onSave={saveWord(hit)},
            onKnown={val known=(prefs.getStringSet("known",emptySet()) ?: emptySet()).toMutableSet(); known.add(hit.key); prefs.edit().putStringSet("known",known).apply(); ScreenReaderState.emit(mapOf("kind" to "changed")); removePanel(); forceCapture()},
            onExplain={loadExplanation(true)},
            onClose={dismissPanel()},
            onRefresh={removePanel(); forceCapture()},
            onStop={stopSelf()},
            onScope={value -> scope.save(prefs, value); removePanel(); forceCapture()},
            onWord={word -> showDetail(word)},
            onParagraph = translateParagraph)
        val params=readingPanelParams()
        applyPanelBackdrop(readingPanel,params)
        readingPanel.setOnTouchListener { _,event -> if(event.action==MotionEvent.ACTION_OUTSIDE) {dismissPanel();true} else false }
        windows.addView(readingPanel,params); panel=readingPanel;NativeReadingStyle.animateIn(readingPanel); loadExplanation()
    }

    private fun dismissPanel() {
        removePanel()
        // Closing a card changes our windows, not the source page. Keep both
        // its analysis key and in-flight translation so it can be reused.
        currentPage?.let { showAnnotations(it,currentHits) }
    }
    private fun showMenu() {
        removePanel();detailOpen=true;clearAnnotations()
        val page = currentPage
        val detectedLanguage = page?.language
        val paragraphs = page?.paragraphs.orEmpty()
        val options = ReadingOptions.load(prefs).resolved(detectedLanguage ?: "en")
        val scope = options.learningScope(detectedLanguage)
        val menu=NativeReadingMenu(this,options,paused,currentHits,
            onClose={dismissPanel()},onPause={setPaused(!paused);dismissPanel()},
            onRefresh={removePanel();forceCapture()},onStop={stopSelf()},
            onScope={value -> scope.save(prefs, value); removePanel()},
            onLanguage={key,value -> prefs.edit().putString(key,value).apply();removePanel()},
            onMode={value->openTranslationWhenReady=false;prefs.edit().putString("readingMode",value).apply();removePanel();ScreenReaderState.emit(mapOf("kind" to "changed"))},
            onPage = {
                if (options.mode == "translation") showPageTranslation()
                else showTranslationPreview(paragraphs, detectedLanguage ?: "auto", wholePage = true)
            },
            paragraphs = paragraphs,
            onParagraph = { showTranslationPreview(listOf(it), detectedLanguage ?: "auto") },
            error=readingError,detectedLanguage=detectedLanguage,scope=scope,
            onWord={showDetail(it)},onApp={
                removePanel()
                startActivity(Intent(this,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
            })
        val metrics=resources.displayMetrics
        val menuWidth=min(dp(360),metrics.widthPixels-dp(24))
        val menuHeight=min(dp(440),(metrics.heightPixels*.72f).toInt())
        val origin=IntArray(2);bubble?.getLocationOnScreen(origin)
        val below=origin[1]+dp(56)
        val top=if(below+menuHeight<=metrics.heightPixels-dp(24)) below else (origin[1]-menuHeight-dp(8)).coerceAtLeast(dp(24))
        val left=(if(origin[0]>metrics.widthPixels/2) origin[0]+dp(48)-menuWidth else origin[0]).coerceIn(dp(12),(metrics.widthPixels-menuWidth-dp(12)).coerceAtLeast(dp(12)))
        val params=GlassAnnotations.overlayParams(menuWidth,menuHeight).apply {
            gravity=Gravity.TOP or Gravity.LEFT;x=left;y=top
            flags=flags or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
        }
        applyPanelBackdrop(menu,params)
        menu.setOnTouchListener { _,event -> if(event.action==MotionEvent.ACTION_OUTSIDE) {dismissPanel();true} else false }
        windows.addView(menu,params);panel=menu;NativeReadingStyle.animateIn(menu)
    }
    private fun emitPageTranslation() {
        val options=ReadingOptions.load(prefs)
        if(currentPageParts.isNotEmpty()) prefs.edit().putString("lastTranslationSegments",JSONArray(currentPageParts.map{it.json()}).toString())
            .putString("lastTranslatedText",currentPage?.text ?: "").putString("lastDetectedLanguage",currentPage?.language ?: "auto").putString("lastTranslationSource",if(options.source=="auto") currentPage?.language ?: "auto" else options.source).putString("lastTranslationTarget",options.target).apply()

        ScreenReaderState.emit(mapOf("kind" to "translation","text" to (currentPage?.text ?: ""),"translationSegments" to currentPageParts.map{it.nativeMap()},"translationLoading" to pageTranslationLoading,"translationError" to pageTranslationError,"detectedLanguage" to (currentPage?.language ?: "auto")))
        if (options.mode == "translation") showParagraphAnnotations()
        if (refreshPreview == null) (panel as? NativePageTranslationPanel)?.show(currentPageParts,pageTranslationLoading,pageTranslationError)
    }
    private fun showPageTranslation() {
        val view = attachTranslationPanel("整页对照") { removePanel(); openTranslationWhenReady = true; forceCapture() }
        view.show(currentPageParts,pageTranslationLoading,pageTranslationError)
    }

    /** A user-selected original stays local to this panel, outside the ongoing reading session. */
    private fun showTranslationPreview(paragraphs: List<PageParagraph>, language: String, wholePage: Boolean = false) {
        val options = ReadingOptions.load(prefs).resolved(language)
        val view = attachTranslationPanel(if (wholePage) "整页对照" else "段落对照", compact = !wholePage) {
            if (paragraphs.isEmpty()) { removePanel(); forceCapture() } else refreshPreview?.invoke()
        }
        fun translate() {
            val ticket = previewRevision.incrementAndGet()
            fun isCurrent() = !stopping && previewRevision.get() == ticket
            view.show(paragraphs, paragraphs.isNotEmpty() && aiAllowed(), null)
            if (paragraphs.isEmpty()) return
            network.execute {
                if (!isCurrent()) return@execute
                var result = paragraphs
                val error = try {
                    translator.translateParagraphs(paragraphs, language, options, ::isCurrent) { snapshot ->
                        result = snapshot
                        main.post { if (isCurrent()) view.show(snapshot, aiAllowed(), null) }
                    }
                    null
                } catch (_: AiConsentRequired) {
                    NativeAiConsent.prompt
                } catch (failure: Exception) {
                    when {
                        !aiAllowed() -> NativeAiConsent.prompt
                        failure.message?.contains("相同语言") == true || failure.message?.contains("12000") == true -> failure.message
                        else -> "翻译暂未完成，原文与已有译文已保留。"
                    }
                }
                main.post {
                    if (isCurrent()) view.show(result, false, error ?: if (aiAllowed()) null else NativeAiConsent.prompt)
                }
            }
        }
        refreshPreview = ::translate
        translate()
    }

    private fun attachTranslationPanel(title: String, compact: Boolean = false, retry: () -> Unit): NativePageTranslationPanel {
        removePanel();detailOpen=true;clearAnnotations()
        val params = readingPanelParams()
        val view = NativePageTranslationPanel(this, onClose = ::dismissPanel, onRetry = retry,
            onStop = ::stopSelf, onSettings = ::showMenu, title = title, maxPanelHeight = params.height.takeIf { compact })
        if (compact) params.height = WindowManager.LayoutParams.WRAP_CONTENT else applyPanelBackdrop(view, params)
        view.setOnTouchListener {_,event->if(event.action==MotionEvent.ACTION_OUTSIDE){dismissPanel();true}else false}
        windows.addView(view,params);panel=view;NativeReadingStyle.animateIn(view)
        return view
    }
    private fun saveWord(hit: WordHit) {
        val old=try { JSONArray(prefs.getString("saved","[]")) } catch (_: Exception) { JSONArray() }
        val next=JSONArray()
        for (i in 0 until old.length()) { val item=old.getJSONObject(i); if (item.optString("studyKey",item.optString("word")) != hit.key) next.put(item) }
        next.put(hit.json()); prefs.edit().putString("saved",next.toString()).apply(); ScreenReaderState.emit(mapOf("kind" to "changed"))
    }
    /** Keep the article visible beside both result panels on unfolded screens. */
    private fun readingPanelParams(): WindowManager.LayoutParams {
        val metrics = resources.displayMetrics
        val wide = metrics.widthPixels / metrics.density >= 680
        val availableWidth = if (wide) (metrics.widthPixels * .48f).toInt() - dp(12)
                             else metrics.widthPixels - dp(24)
        return GlassAnnotations.overlayParams(min(dp(440),availableWidth), (metrics.heightPixels * .72f).toInt()).apply {
            flags = flags or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
            gravity = Gravity.BOTTOM or if (wide) Gravity.RIGHT else Gravity.CENTER_HORIZONTAL
            if (wide) x = dp(12)
            y = dp(26)
        }
    }
    private fun applyPanelBackdrop(view:View,params:WindowManager.LayoutParams) {
        val source=lastClean ?: return
        if(source.isRecycled) return
        val screen=resources.displayMetrics
        val horizontal=params.gravity and Gravity.HORIZONTAL_GRAVITY_MASK
        val left=when(horizontal) {Gravity.RIGHT->screen.widthPixels-params.width-params.x;Gravity.CENTER_HORIZONTAL->(screen.widthPixels-params.width)/2+params.x;else->params.x}
        val top=if(params.gravity and Gravity.VERTICAL_GRAVITY_MASK==Gravity.BOTTOM) screen.heightPixels-params.height-params.y else params.y
        val sx=source.width.toFloat()/screen.widthPixels;val sy=source.height.toFloat()/screen.heightPixels
        view.background=NativeReadingStyle.glass(this,NativeGlassBackdrop.sample(source,RectF(left*sx,top*sy,(left+params.width)*sx,(top+params.height)*sy)))
    }
    private fun removePanel() {
        previewRevision.incrementAndGet()
        refreshPreview = null
        panel?.let { try { windows.removeView(it) } catch (_: Exception) {}; (it.background as? GlassDrawable)?.release() }
        panel = null; detailOpen = false
    }
    private fun fail(message:String) { readingError=message;ScreenReaderState.emit(mapOf("kind" to "error","message" to message)); Log.d("LingferScreen","Reading is waiting for a usable page or connection") }
    private fun dp(value:Int)=(value*resources.displayMetrics.density).toInt()
    private fun chromeTop(height: Int) = OcrNoise.chromeHeight(height, dp(40).toFloat(), 0.04f, 0.08f)
    private fun chromeBottom(height: Int) = OcrNoise.chromeHeight(height, dp(28).toFloat(), 0.03f, 0.07f)

    private fun sample(image:Image, own:List<RectF>):IntArray {
        val plane=image.planes[0]; val buffer=plane.buffer; val values=IntArray(64*72)
        val topBand = chromeTop(image.height)
        val bottomBand = chromeBottom(image.height)
        for (y in 0 until 72) for (x in 0 until 64) {
            val px=((x+.5f)*image.width/64).toInt().coerceIn(0,image.width-1); val py=((y+.5f)*image.height/72).toInt().coerceIn(0,image.height-1)
            if (py < topBand || py > image.height - bottomBand || own.any { it.contains(px.toFloat(), py.toFloat()) }) { values[y*64+x]=-1;continue }
            val index=py*plane.rowStride+px*plane.pixelStride
            val r=buffer.get(index).toInt() and 255;val g=buffer.get(index+1).toInt() and 255;val b=buffer.get(index+2).toInt() and 255
            values[y*64+x]=(r*3+g*6+b)/10
        };return values
    }
    private fun distance(a:IntArray,b:IntArray):Float { var changed=0;var compared=0;for(i in a.indices) if(a[i]>=0 && b[i]>=0){compared++;if(abs(a[i]-b[i])>24)changed++};return if(compared==0)0f else changed.toFloat()/compared }
    private fun bitmap(image:Image):Bitmap { val plane=image.planes[0]; val paddedWidth=image.width+(plane.rowStride-plane.pixelStride*image.width)/plane.pixelStride; val padded=Bitmap.createBitmap(paddedWidth,image.height,Bitmap.Config.ARGB_8888);padded.copyPixelsFromBuffer(plane.buffer);val bitmap=Bitmap.createBitmap(padded,0,0,image.width,image.height);if(bitmap!==padded)padded.recycle();return bitmap }

    @Suppress("DEPRECATION") override fun onDestroy() {
        stopping=true;revision.incrementAndGet();prefs.unregisterOnSharedPreferenceChangeListener(this)
        aiConsentPrefs.unregisterOnSharedPreferenceChangeListener(this)
        main.removeCallbacksAndMessages(null);frames.removeCallbacksAndMessages(null)
        clearAnnotations();removePanel();bubble?.let { try { windows.removeView(it) } catch (_:Exception){} };bubble=null
        display?.release();display=null;reader?.close();reader=null
        projection?.unregisterCallback(projectionCallback);projection?.stop();projection=null
        ocr.close();if(translatorHolder.isInitialized())translator.close();network.shutdownNow();framesThread.quitSafely()
        candidate?.takeUnless { it.isRecycled || it===lastClean }?.recycle();lastClean?.takeUnless { it.isRecycled }?.recycle()
        ScreenReaderState.running=false;ScreenReaderState.paused=false;ScreenReaderState.emit(mapOf("kind" to "status","running" to false,"paused" to false))
        if(Build.VERSION.SDK_INT>=24)stopForeground(STOP_FOREGROUND_REMOVE)else stopForeground(true)
        super.onDestroy()
    }
}
