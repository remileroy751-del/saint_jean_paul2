package com.connecttest.app

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Palette du Complexe Scolaire : bleu marine + jaune pâle du logo. Le Primaire ajoute un peu de rose. */
private object Palette {
    var level by mutableStateOf("college")
    val primaire: Boolean get() = level == "primaire"
}

private val Navy = Color(0xFF040678)
private val LogoYellow = Color(0xFFFCEE76)
private val PaleYellow = Color(0xFFFFF9D2)
private val Pink = Color(0xFFEC5F9E)
private val PalePink = Color(0xFFFDE7F1)
private val Black = Color(0xFF111111)
private val White = Color(0xFFFFFFFF)

private val Kaki: Color get() = Navy
private val Beurre: Color get() = if (Palette.primaire) Color(0xFFFFF1F7) else PaleYellow
private val DarkGreen: Color get() = Navy
private val YellowGreen: Color get() = Navy
private val SoftGreen: Color get() = if (Palette.primaire) PalePink else PaleYellow
private val Orange: Color get() = LogoYellow
private val Red = Color(0xFFB3261E)
private val Accent: Color get() = if (Palette.primaire) Pink else Navy
private val HeaderBg: Color get() = if (Palette.primaire) PalePink else PaleYellow

data class Child(val id: String, val name: String, val className: String, val level: String)
data class Teacher(val id: String, val name: String, val subject: String, val homeroom: Boolean)
data class NoteRow(
    val subject: String,
    val homework: List<Pair<String, Double>>,
    val classAverage: Double?,
    val composition: Double?,
    val subjectAverage: Double?
)
data class Announcement(
    val id: String, val title: String, val body: String,
    val importance: String, val createdAt: String, val isRead: Boolean
)
data class ChatMessage(val id: String, val senderRole: String, val body: String, val createdAt: String)
data class TeacherClass(
    val classId: String, val className: String, val subjectId: String,
    val subjectName: String, val assignmentId: String, val homeroom: Boolean, val level: String
)
data class Student(val id: String, val name: String, val className: String)
data class ClassStat(val classId: String, val className: String, val effectif: Int)
data class StudentRanking(val id: String, val name: String, val generalAverage: Double?)
data class TeacherConversation(val parentId: String, val parentName: String, val studentId: String, val studentName: String, val className: String, val lastMessage: String, val lastSenderRole: String, val lastMessageAt: String)
data class Payment(val no: Int, val amount: Double, val paidAt: String)
data class FeeInfo(val defined: Boolean, val className: String, val totalDue: Double, val paid: Double, val remaining: Double, val payments: List<Payment>)
data class MenuDate(val date: String, val dish: String, val photoCount: Int)
data class CanteenDay(val exists: Boolean, val date: String, val dishName: String, val description: String, val staffName: String, val photos: List<String>, val locked: Boolean)
data class MobileNotification(val id: String, val title: String, val body: String, val createdAt: String)

class ConnectTestApi {
    private val base = BuildConfig.SUPABASE_URL.trimEnd('/')
    private val key = BuildConfig.SUPABASE_ANON_KEY

    private fun post(function: String, body: JSONObject): String {
        val conn = (URL("$base/rest/v1/rpc/$function").openConnection() as HttpURLConnection)
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 20000
            conn.readTimeout = 30000
            conn.setRequestProperty("apikey", key)
            conn.setRequestProperty("Authorization", "Bearer $key")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            if (code !in 200..299) error(text.ifBlank { "Erreur HTTP $code" })
            return text
        } finally { conn.disconnect() }
    }

    private fun arr(text: String) = JSONArray(text)
    private fun dateLabel(raw: String): String = runCatching {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        val output = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.FRANCE)
        output.format(input.parse(raw.take(19)) ?: Date())
    }.getOrDefault(raw.take(16).replace('T', ' '))

    fun login(code: String): JSONObject = post("login_with_access_code", JSONObject().put("p_code", code.trim().uppercase()))
        .let { if (it.trimStart().startsWith("[") && JSONArray(it).length() > 0) JSONArray(it).getJSONObject(0) else JSONObject(it) }

    fun parentChildren(code: String): List<Child> = arr(post("parent_children", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { o -> a.getJSONObject(o).let { Child(it.getString("student_id"), it.getString("student_name"), it.getString("class_name"), it.optString("level", "college")) } }
    }

    fun teachersForChild(code: String, childId: String): List<Teacher> = arr(post("parent_child_teachers", JSONObject().put("p_code", code).put("p_student_id", childId))).let { a ->
        (0 until a.length()).map { o -> a.getJSONObject(o).let { Teacher(it.getString("teacher_id"), it.getString("teacher_name"), it.getString("subject_name"), it.optBoolean("is_homeroom")) } }
    }

    fun notes(code: String, childId: String, term: String): List<NoteRow> = arr(post("student_notes", JSONObject().put("p_code", code).put("p_student_id", childId).put("p_term", term))).let { a ->
        (0 until a.length()).map { i ->
            val o = a.getJSONObject(i)
            val hw = mutableListOf<Pair<String, Double>>()
            val ja = o.optJSONArray("devoirs") ?: JSONArray()
            for (j in 0 until ja.length()) {
                val h = ja.getJSONObject(j)
                hw += (h.optString("title").ifBlank { "Devoir" }) to h.optDouble("value", 0.0)
            }
            NoteRow(o.optString("subject_name"), hw, o.takeDouble("moyenne_classe"), o.takeDouble("composition"), o.takeDouble("moyenne_matiere"))
        }
    }

    fun announcements(code: String, childId: String): List<Announcement> = arr(post("student_announcements", JSONObject().put("p_code", code).put("p_student_id", childId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Announcement(it.getString("announcement_id"), it.optString("title"), it.optString("body"), it.optString("importance"), dateLabel(it.optString("created_at")), it.optBoolean("is_read")) } }
    }

    fun markAnnouncementsRead(code: String, childId: String) {
        post("mark_announcements_read", JSONObject().put("p_code", code).put("p_student_id", childId))
    }

    fun teacherAnnouncements(code: String): List<Announcement> = arr(post("teacher_announcements", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Announcement(it.getString("announcement_id"), it.optString("title"), it.optString("body"), it.optString("importance"), dateLabel(it.optString("created_at")), false) } }
    }

    fun messages(code: String, childId: String, teacherId: String): List<ChatMessage> = arr(post("conversation_messages", JSONObject().put("p_code", code).put("p_student_id", childId).put("p_teacher_id", teacherId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { ChatMessage(it.getString("message_id"), it.optString("sender_role"), it.optString("body"), dateLabel(it.optString("created_at"))) } }
    }

    fun sendParentMessage(code: String, childId: String, teacherId: String, body: String) {
        post("send_parent_message", JSONObject().put("p_code", code).put("p_student_id", childId).put("p_teacher_id", teacherId).put("p_body", body))
    }

    fun teacherConversations(code: String): List<TeacherConversation> = arr(post("teacher_conversations", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let {
            TeacherConversation(
                it.getString("parent_id"), it.getString("parent_name"), it.getString("student_id"),
                it.getString("student_name"), it.getString("class_name"), it.optString("last_message"),
                it.optString("last_sender_role"), dateLabel(it.optString("last_message_at"))
            )
        } }
    }

    fun teacherMessages(code: String, studentId: String, parentId: String): List<ChatMessage> = arr(post("teacher_conversation_messages", JSONObject().put("p_code", code).put("p_student_id", studentId).put("p_parent_id", parentId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { ChatMessage(it.getString("message_id"), it.optString("sender_role"), it.optString("body"), dateLabel(it.optString("created_at"))) } }
    }

    fun sendTeacherMessage(code: String, studentId: String, parentId: String, body: String) {
        post("teacher_send_parent_message", JSONObject().put("p_code", code).put("p_student_id", studentId).put("p_parent_id", parentId).put("p_body", body))
    }

    fun teacherClassStats(code: String, term: String): List<ClassStat> = arr(post("teacher_class_statistics", JSONObject().put("p_code", code).put("p_term", term))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { ClassStat(it.getString("class_id"), it.getString("class_name"), it.optInt("effectif")) } }
    }

    fun teacherRankings(code: String, classId: String, term: String): List<StudentRanking> = arr(post("teacher_student_rankings", JSONObject().put("p_code", code).put("p_class_id", classId).put("p_term", term))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { StudentRanking(it.getString("student_id"), it.getString("student_name"), it.takeDouble("moyenne_generale")) } }
    }

    fun teacherClasses(code: String): List<TeacherClass> = arr(post("teacher_classes", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { TeacherClass(it.getString("class_id"), it.getString("class_name"), it.getString("subject_id"), it.getString("subject_name"), it.getString("assignment_id"), it.optBoolean("is_homeroom"), it.optString("level", "college")) } }
    }

    fun mobileNotifications(code: String, role: String, since: String): List<MobileNotification> = arr(post("mobile_notifications", JSONObject().put("p_code", code).put("p_role", role).put("p_since", since))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { MobileNotification(it.getString("notification_id"), it.optString("title"), it.optString("body"), it.getString("created_at")) } }
    }

    /** Heure du serveur (UTC) : sert de point de départ fiable aux notifications, même si l'horloge du téléphone est fausse. */
    fun serverTimeOrNull(): String? = runCatching {
        post("mobile_server_time", JSONObject()).trim().trim('"').takeIf { it.length >= 19 }
    }.getOrNull()

    fun teacherStudents(code: String, classId: String): List<Student> = arr(post("teacher_students", JSONObject().put("p_code", code).put("p_class_id", classId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Student(it.getString("student_id"), it.getString("student_name"), it.getString("class_name")) } }
            .sortedBy { it.name.lowercase(Locale.FRANCE) }
    }

    fun parentFees(code: String, studentId: String): FeeInfo {
        val o = JSONObject(post("parent_fees", JSONObject().put("p_code", code).put("p_student_id", studentId)))
        val pa = o.optJSONArray("payments") ?: JSONArray()
        val list = (0 until pa.length()).map { i -> pa.getJSONObject(i).let { Payment(it.optInt("installment_no"), it.optDouble("amount", 0.0), it.str("paid_at")) } }
        return FeeInfo(o.optBoolean("defined"), o.str("class_name"), o.optDouble("total_due", 0.0), o.optDouble("paid", 0.0), o.optDouble("remaining", 0.0), list)
    }

    private fun parseCanteenDay(o: JSONObject): CanteenDay {
        val pa = o.optJSONArray("photos") ?: JSONArray()
        val photos = (0 until pa.length()).map { pa.getString(it) }
        val date = if (o.has("date")) o.str("date") else o.str("menu_date")
        return CanteenDay(o.optBoolean("exists", false), date, o.str("dish_name"), o.str("description"), o.str("staff_name"), photos, o.optBoolean("locked", photos.size >= 2))
    }

    fun canteenDates(code: String): List<MenuDate> = arr(post("canteen_menu_dates", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { MenuDate(it.str("menu_date"), it.str("dish_name"), it.optInt("photo_count")) } }
    }

    fun canteenMenu(code: String, date: String): CanteenDay =
        parseCanteenDay(JSONObject(post("canteen_menu_for_date", JSONObject().put("p_code", code).put("p_date", date))))

    fun canteenToday(code: String): CanteenDay =
        parseCanteenDay(JSONObject(post("canteen_today", JSONObject().put("p_code", code))))

    fun canteenSaveMenu(code: String, dish: String, description: String) {
        post("canteen_save_menu", JSONObject().put("p_code", code).put("p_dish_name", dish).put("p_description", if (description.isBlank()) JSONObject.NULL else description))
    }

    fun canteenAddPhoto(code: String, imageBase64: String) {
        post("canteen_add_photo", JSONObject().put("p_code", code).put("p_image", imageBase64))
    }

    fun canteenAnnouncements(code: String): List<Announcement> = arr(post("canteen_announcements", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Announcement(it.getString("announcement_id"), it.optString("title"), it.optString("body"), it.optString("importance"), dateLabel(it.optString("created_at")), false) } }
    }

    fun saveNote(code: String, studentId: String, assignmentId: String, term: String, noteType: String, value: Double, title: String?) {
        post("teacher_save_note", JSONObject().put("p_code", code).put("p_student_id", studentId).put("p_assignment_id", assignmentId).put("p_term", term).put("p_note_type", noteType).put("p_value", value).put("p_title", title ?: JSONObject.NULL))
    }
}

private fun JSONObject.str(key: String): String = if (isNull(key)) "" else optString(key)

private fun JSONObject.takeDouble(key: String): Double? = if (!has(key) || isNull(key)) null else optDouble(key).takeIf { !it.isNaN() }

/** État partagé : l'écran est-il visible ? Permet d'actualiser les messages seulement quand l'app est au premier plan. */
private object AppForeground {
    var active by mutableStateOf(false)
    var resumeTick by mutableStateOf(0)
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("connect_test_local", Context.MODE_PRIVATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
        }
        setContent { ConnectTestApp(prefs, this) }
    }

    override fun onStart() { super.onStart(); AppForeground.active = true }
    override fun onResume() { super.onResume(); AppForeground.resumeTick = AppForeground.resumeTick + 1 }
    override fun onStop() { AppForeground.active = false; super.onStop() }
}

/** Relance périodique d'une actualisation tant que l'application est visible (messages reçus en direct dans l'écran ouvert). */
@Composable
private fun PollWhileVisible(intervalMs: Long, block: suspend () -> Unit) {
    val current by rememberUpdatedState(block)
    val active = AppForeground.active
    LaunchedEffect(active) {
        if (active) {
            while (true) {
                delay(intervalMs)
                try { current() } catch (e: CancellationException) { throw e } catch (_: Exception) { }
            }
        }
    }
}

private fun isIgnoringBatteryOptimizations(context: Context): Boolean = runCatching {
    (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName)
}.getOrDefault(true)

private fun requestIgnoreBatteryOptimizations(context: Context) {
    runCatching {
        context.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply { data = Uri.parse("package:${context.packageName}") })
    }.onFailure {
        runCatching { context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
    }
}

private fun openNotificationSettings(context: Context) {
    runCatching {
        context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
    }
}

/** Guide l'utilisateur pour que les notifications s'affichent en haut de l'écran et arrivent même application fermée. */
@Composable
private fun BackgroundSetupDialogs(activity: MainActivity, prefs: android.content.SharedPreferences) {
    val tick = AppForeground.resumeTick
    var notifDismissed by remember { mutableStateOf(false) }
    var batteryDone by remember { mutableStateOf(prefs.getBoolean("battery_prompt_done", false)) }
    val notificationsOn = remember(tick) { NotificationManagerCompat.from(activity).areNotificationsEnabled() }
    val batteryOk = remember(tick) { isIgnoringBatteryOptimizations(activity) }
    if (!notificationsOn && !notifDismissed) {
        AlertDialog(
            onDismissRequest = { notifDismissed = true },
            title = { Text("Activer les notifications") },
            text = { Text("Pour être averti(e) dès qu'un message arrive, en haut de l'écran de votre téléphone, autorisez les notifications de l'application.") },
            confirmButton = { TextButton(onClick = { notifDismissed = true; openNotificationSettings(activity) }) { Text("Ouvrir les paramètres") } },
            dismissButton = { TextButton(onClick = { notifDismissed = true }) { Text("Plus tard") } }
        )
    } else if (notificationsOn && !batteryOk && !batteryDone) {
        AlertDialog(
            onDismissRequest = { batteryDone = true; prefs.edit().putBoolean("battery_prompt_done", true).apply() },
            title = { Text("Rester connecté en arrière-plan") },
            text = { Text("Pour recevoir les messages même quand l'application est fermée ou que le téléphone est en veille, autorisez l'application à fonctionner en arrière-plan sans restriction de batterie.") },
            confirmButton = { TextButton(onClick = { batteryDone = true; prefs.edit().putBoolean("battery_prompt_done", true).apply(); requestIgnoreBatteryOptimizations(activity) }) { Text("Autoriser") } },
            dismissButton = { TextButton(onClick = { batteryDone = true; prefs.edit().putBoolean("battery_prompt_done", true).apply() }) { Text("Plus tard") } }
        )
    }
}

@Composable
private fun ConnectTestApp(prefs: android.content.SharedPreferences, activity: MainActivity) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Kaki,
            onPrimary = White,
            primaryContainer = Beurre,
            onPrimaryContainer = Black,
            secondary = Beurre,
            onSecondary = Black,
            secondaryContainer = Kaki,
            onSecondaryContainer = White,
            tertiary = Kaki,
            onTertiary = White,
            background = White,
            onBackground = Black,
            surface = White,
            onSurface = Black,
            surfaceVariant = Beurre,
            onSurfaceVariant = Black,
            outline = Kaki,
            outlineVariant = Kaki,
            inverseSurface = Black,
            inverseOnSurface = White,
            inversePrimary = Beurre,
            scrim = Black
        )
    ) {
        Surface(Modifier.fillMaxSize(), color = White) {
            var code by remember { mutableStateOf(prefs.getString("last_access_code", "") ?: "") }
            var role by remember { mutableStateOf<String?>(prefs.getString("last_role", null)) }
            var profileName by remember { mutableStateOf(prefs.getString("last_profile_name", "") ?: "") }
            var error by remember { mutableStateOf("") }
            var loading by remember { mutableStateOf(false) }
            val api = remember { ConnectTestApi() }
            val scope = rememberCoroutineScope()

            LaunchedEffect(Unit) {
                val savedCode = prefs.getString("last_access_code", "") ?: ""
                if (savedCode.isNotBlank() && (role == null || profileName.isBlank())) {
                    loading = true
                    runCatching {
                        withContext(Dispatchers.IO) { api.login(savedCode) }
                    }.onSuccess { r ->
                        if (r.optBoolean("success", false)) {
                            role = r.optString("role")
                            profileName = r.optString("full_name")
                            prefs.edit().putString("last_role", role).putString("last_profile_name", profileName).apply()
                            startConnectTestNotificationService(activity)
                        } else {
                            prefs.edit().clear().apply()
                            code = ""; role = null; profileName = ""
                        }
                    }.onFailure {
                        // En cas de réseau indisponible, on garde la session locale et réessaiera au prochain lancement.
                    }
                    loading = false
                } else if (role != null && code.isNotBlank()) {
                    startConnectTestNotificationService(activity)
                    // Vérification silencieuse : la session n'est effacée que si la Direction a réellement supprimé/changé le code.
                    runCatching { withContext(Dispatchers.IO) { api.login(code) } }.onSuccess { r ->
                        if (r.has("success") && !r.optBoolean("success", true)) {
                            stopConnectTestNotificationService(activity)
                            prefs.edit().clear().apply()
                            code = ""; role = null; profileName = ""
                        } else if (r.optString("full_name").isNotBlank() && r.optString("full_name") != profileName) {
                            profileName = r.optString("full_name")
                            prefs.edit().putString("last_profile_name", profileName).apply()
                        }
                    }
                }
            }

            if (role != null) BackgroundSetupDialogs(activity, prefs)
            if (role == null) {
                LoginScreen(code, { code = it }, error, loading) {
                    loading = true; error = ""
                    scope.launch {
                        try {
                            val r = withContext(Dispatchers.IO) { api.login(code) }
                            if (!r.optBoolean("success", false)) {
                                error = r.optString("message", "Code incorrect.")
                            } else {
                                val normalized = code.trim().uppercase()
                                val cursor = withContext(Dispatchers.IO) { api.serverTimeOrNull() } ?: java.time.Instant.now().minusSeconds(90).toString()
                                code = normalized
                                role = r.optString("role")
                                profileName = r.optString("full_name")
                                prefs.edit()
                                    .putString("last_access_code", normalized)
                                    .putString("last_role", role)
                                    .putString("last_profile_name", profileName)
                                    .putString("notification_cursor", cursor)
                                    .putString("notified_ids", "")
                                    .apply()
                                startConnectTestNotificationService(activity)
                            }
                        } catch (e: Exception) {
                            error = "Connexion impossible : ${e.message?.take(140) ?: "erreur réseau ou serveur"}"
                        } finally { loading = false }
                    }
                }
            } else if (role == "parent") {
                ParentHome(api, code, profileName, onExit = { activity.moveTaskToBack(true) }) {
                    stopConnectTestNotificationService(activity)
                    prefs.edit().clear().apply()
                    code = ""; role = null; profileName = ""
                }
            } else if (role == "canteen") {
                CanteenHome(api, code, profileName, onExit = { activity.moveTaskToBack(true) }) {
                    stopConnectTestNotificationService(activity)
                    prefs.edit().clear().apply()
                    code = ""; role = null; profileName = ""
                }
            } else {
                TeacherHome(api, code, profileName, onExit = { activity.moveTaskToBack(true) }) {
                    stopConnectTestNotificationService(activity)
                    prefs.edit().clear().apply()
                    code = ""; role = null; profileName = ""
                }
            }
        }
    }
}

@Composable
private fun LoginScreen(code: String, onCode: (String) -> Unit, error: String, loading: Boolean, onLogin: () -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 26.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("République Togolaise", color = Navy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(8.dp))
            TogoFlag(Modifier.size(width = 27.dp, height = 18.dp))
        }
        Spacer(Modifier.height(14.dp))
        Image(
            painterResource(R.drawable.sjp2_logo),
            contentDescription = "Logo Complexe Scolaire SAINT JEAN PAUL II",
            modifier = Modifier.size(130.dp),
            contentScale = ContentScale.Fit
        )
        Spacer(Modifier.height(12.dp))
        Text("Complexe Scolaire", color = Navy, fontSize = 25.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
        Text("SAINT JEAN PAUL II", color = Navy, fontSize = 31.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center, lineHeight = 36.sp)
        Spacer(Modifier.height(22.dp))
        OutlinedTextField(
            value = code,
            onValueChange = { onCode(it.filter(Char::isLetterOrDigit).take(6).uppercase()) },
            label = { Text("Code d'accès") },
            placeholder = { Text("Saisissez votre code") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp)
        )
        Spacer(Modifier.height(14.dp))
        Button(
            onClick = onLogin,
            enabled = code.length in 4..6 && !loading,
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(16.dp)
        ) {
            Text(if (loading) "Connexion..." else "ACCÉDER À MON ESPACE", fontWeight = FontWeight.Bold)
        }
        if (error.isNotBlank()) {
            Spacer(Modifier.height(12.dp))
            Text(error, color = Red, fontSize = 13.sp)
        }
        Spacer(Modifier.height(26.dp))
        Surface(shape = RoundedCornerShape(18.dp), color = PaleYellow, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Système de suivi de Scolarité", color = Navy, fontSize = 15.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center)
                Spacer(Modifier.height(4.dp))
                Text("Contact permanent Enseignant / Parent / Direction", color = Navy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
private fun Header(title: String, subtitle: String, logout: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(bottom = 18.dp),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = HeaderBg),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Image(
                painterResource(R.drawable.sjp2_logo),
                contentDescription = "Logo Saint Jean Paul II",
                modifier = Modifier.size(62.dp),
                contentScale = ContentScale.Fit
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("SAINT JEAN PAUL II", color = Accent, fontWeight = FontWeight.Black, fontSize = 12.sp)
                Text(title, color = DarkGreen, fontWeight = FontWeight.Black, fontSize = 20.sp)
                Text(if (subtitle.isNotBlank()) subtitle else "Système de suivi de Scolarité", color = Kaki, fontSize = 10.sp)
            }
            IconButton(onClick = logout) {
                Icon(Icons.Default.Logout, "Déconnexion", tint = DarkGreen)
            }
        }
    }
}

@Composable
private fun ParentHome(api: ConnectTestApi, code: String, parentName: String, onExit: () -> Unit, logout: () -> Unit) {
    var children by remember { mutableStateOf<List<Child>>(emptyList()) }
    var selected by remember { mutableStateOf<Child?>(null) }
    var error by remember { mutableStateOf("") }
    BackHandler { if (selected != null) selected = null else onExit() }
    val parentLevel = selected?.level ?: "college"
    SideEffect { Palette.level = parentLevel }
    DisposableEffect(Unit) { onDispose { Palette.level = "college" } }
    LaunchedEffect(Unit) { try { children = withContext(Dispatchers.IO) { api.parentChildren(code) } } catch (_: Exception) { error = "Impossible de charger les enfants." } }
    if (selected == null) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            Header("ESPACE PARENT", "", logout)
            Text("Bienvenu(e) Mr/Mme $parentName", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
            Spacer(Modifier.height(8.dp))
            Text("Mes enfants", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
            Spacer(Modifier.height(12.dp))
            if (error.isNotBlank()) Text(error, color = Red)
            if (children.isEmpty() && error.isBlank()) Text("Aucun enfant lié à ce compte.", color = Kaki)
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) { items(children) { child ->
                Card(Modifier.fillMaxWidth().clickable { selected = child }, shape = RoundedCornerShape(20.dp)) {
                    Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(52.dp).background(SoftGreen, RoundedCornerShape(16.dp)), Alignment.Center) { Text(child.name.take(1).uppercase(), color = DarkGreen, fontSize = 22.sp, fontWeight = FontWeight.Bold) }
                        Spacer(Modifier.width(14.dp)); Column { Text(child.name, fontSize = 18.sp, fontWeight = FontWeight.Bold); Text(child.className, color = Kaki) }; Spacer(Modifier.weight(1f)); Icon(Icons.Default.ChevronRight, null)
                    }
                }
            } }
        }
    } else ParentChildScreen(api, code, selected!!, { selected = null })
}

@Composable
private fun ParentChildScreen(api: ConnectTestApi, code: String, child: Child, back: () -> Unit) {
    var page by remember { mutableStateOf("menu") }
    var unreadDirection by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    BackHandler { if (page == "menu") back() else page = "menu" }
    LaunchedEffect(child.id) {
        runCatching {
            val list = withContext(Dispatchers.IO) { api.announcements(code, child.id) }
            unreadDirection = list.count { !it.isRead }
        }
    }
    PollWhileVisible(15_000L) {
        if (page == "menu") {
            runCatching {
                val list = withContext(Dispatchers.IO) { api.announcements(code, child.id) }
                unreadDirection = list.count { !it.isRead }
            }
        }
    }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = { if (page == "menu") back() else page = "menu" }) { Icon(Icons.Default.ArrowBack, "Retour") }; Column { Text(child.name, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen); Text(child.className, color = Kaki) } }
        Spacer(Modifier.height(20.dp))
        when (page) {
            "menu" -> {
                ParentAction("Voir les notes", Icons.Default.School) { page = "notes" }
                ParentAction(
                    "Message de la Direction",
                    Icons.Default.Campaign,
                    if (unreadDirection > 0) "${unreadDirection} nouveau${if (unreadDirection > 1) "x" else ""} message${if (unreadDirection > 1) "s" else ""}" else null
                ) {
                    unreadDirection = 0
                    scope.launch { runCatching { withContext(Dispatchers.IO) { api.markAnnouncementsRead(code, child.id) } } }
                    page = "news"
                }
                ParentAction("Voir les enseignants de mon enfant", Icons.Default.Groups) { page = "chat" }
                ParentAction("Frais de scolarité", Icons.Default.Payments) { page = "fees" }
                ParentAction("Cantine : ce que mon enfant a mangé", Icons.Default.Restaurant) { page = "canteen" }
            }
            "notes" -> NotesScreen(api, code, child) { page = "menu" }
            "news" -> NewsScreen(api, code, child) { page = "menu" }
            "chat" -> ChatScreen(api, code, child) { page = "menu" }
            "fees" -> FeesScreen(api, code, child) { page = "menu" }
            "canteen" -> CanteenViewer(api, code, "Cantine", "Repas de ${child.name}") { page = "menu" }
        }
    }
}

@Composable
private fun ParentAction(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, badge: String? = null, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(vertical = 7.dp).clickable(onClick = onClick), shape = RoundedCornerShape(18.dp)) {
        Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Accent, modifier = Modifier.size(30.dp))
            Spacer(Modifier.width(18.dp))
            Column(Modifier.weight(1f)) {
                Text(label, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                if (!badge.isNullOrBlank()) {
                    Spacer(Modifier.height(3.dp))
                    Text(badge, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Red)
                }
            }
            Icon(Icons.Default.ChevronRight, null)
        }
    }
}

@Composable
private fun TermTabs(selected: String, set: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("1er trimestre", "2e trimestre", "3e trimestre").forEach { FilterChip(selected = selected == it, onClick = { set(it) }, label = { Text(it, fontSize = 11.sp) }) } }
}

@Composable
private fun NotesScreen(api: ConnectTestApi, code: String, child: Child, back: () -> Unit) {
    var term by remember { mutableStateOf("1er trimestre") }
    var rows by remember { mutableStateOf<List<NoteRow>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    BackHandler { back() }
    LaunchedEffect(term) { loading = true; runCatching { rows = withContext(Dispatchers.IO) { api.notes(code, child.id, term) } }; loading = false }
    val averages = rows.mapNotNull { it.subjectAverage }
    val general = averages.takeIf { it.isNotEmpty() }?.average()
    Column(Modifier.fillMaxSize()) {
        Text("Notes & moyennes", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        Spacer(Modifier.height(10.dp)); TermTabs(term) { term = it }; Spacer(Modifier.height(14.dp))
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp)) { Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("GRANDE MOYENNE GÉNÉRALE", color = Kaki, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(5.dp)); Text(general?.let { String.format(Locale.FRANCE, "%.2f / 20", it) } ?: "En attente des notes", fontSize = 38.sp, fontWeight = FontWeight.Black, color = DarkGreen)
            Text("Moyenne de toutes les moyennes de matières", color = Kaki, fontSize = 11.sp)
        } }
        Spacer(Modifier.height(12.dp)); if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(rows) { n -> Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) { Column(Modifier.padding(15.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(n.subject, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f)); Text(n.subjectAverage?.let { String.format(Locale.FRANCE, "%.2f", it) } ?: "—", fontSize = 25.sp, fontWeight = FontWeight.Bold, color = DarkGreen) }; Spacer(Modifier.height(7.dp)); Text("Moyenne de classe : ${n.classAverage?.let { String.format(Locale.FRANCE, "%.2f", it) } ?: "—"}", fontSize = 14.sp, color = Kaki); Text("Composition : ${n.composition?.let { String.format(Locale.FRANCE, "%.2f", it) } ?: "—"}", fontSize = 14.sp, color = Kaki); n.homework.forEach { Text("${it.first} : ${String.format(Locale.FRANCE, "%.2f", it.second)}", fontSize = 14.sp) } } } } }
    }
}

@Composable
private fun NewsScreen(api: ConnectTestApi, code: String, child: Child, back: () -> Unit) {
    var items by remember { mutableStateOf<List<Announcement>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() {
        scope.launch {
            loading = true
            error = ""
            runCatching { withContext(Dispatchers.IO) { api.announcements(code, child.id) } }
                .onSuccess { items = it }
                .onFailure { error = it.message ?: "Impossible de charger les messages de la Direction." }
            loading = false
        }
    }
    LaunchedEffect(child.id) {
        runCatching { withContext(Dispatchers.IO) { api.markAnnouncementsRead(code, child.id) } }
        refresh()
    }
    PollWhileVisible(20_000L) {
        runCatching { withContext(Dispatchers.IO) { api.announcements(code, child.id) } }
            .onSuccess { items = it; error = "" }
            .onFailure { error = it.message ?: "Actualisation impossible." }
    }
    Column(Modifier.fillMaxSize()) {
        Text("Message de la Direction", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        Spacer(Modifier.height(12.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (error.isNotBlank()) {
            Spacer(Modifier.height(8.dp))
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp), colors = CardDefaults.cardColors(containerColor = Beurre)) {
                Text("Erreur : $error", modifier = Modifier.padding(14.dp), color = Black, fontSize = 12.sp)
            }
        }
        if (!loading && error.isBlank() && items.isEmpty()) {
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Beurre)) {
                Text("Aucun message de la Direction pour le moment.", modifier = Modifier.padding(18.dp), color = Black)
            }
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(items) { n ->
                val c = when (n.importance) { "urgent", "rouge" -> Red; else -> YellowGreen }
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                    Column(Modifier.padding(16.dp)) {
                        Text(n.title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                        Text(n.createdAt, color = Kaki, fontSize = 11.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(n.body)
                        Spacer(Modifier.height(10.dp))
                        Surface(
                            shape = RoundedCornerShape(10.dp),
                            color = if (n.isRead) Beurre else c.copy(alpha = 0.18f)
                        ) {
                            Text(
                                if (n.isRead) "Message consulté" else "Nouveau message",
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (n.isRead) Kaki else c
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChatScreen(api: ConnectTestApi, code: String, child: Child, back: () -> Unit) {
    var teachers by remember { mutableStateOf<List<Teacher>>(emptyList()) }; var teacher by remember { mutableStateOf<Teacher?>(null) }
    BackHandler { if (teacher == null) back() else teacher = null }
    LaunchedEffect(Unit) { runCatching { teachers = withContext(Dispatchers.IO) { api.teachersForChild(code, child.id) } } }
    if (teacher == null) { Column(Modifier.fillMaxSize()) { Text("Enseignants de mon enfant", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen); Spacer(Modifier.height(6.dp)); Text("Cliquez sur le nom d'un enseignant pour lui envoyer un message", color = Kaki, fontSize = 12.sp); Spacer(Modifier.height(10.dp)); teachers.forEach { t -> ParentAction("${t.name} • ${t.subject}${if (t.homeroom) " • Titulaire" else ""}", Icons.Default.Person) { teacher = t } } } }
    else Conversation(api, code, child, teacher!!, { teacher = null })
}

@Composable
private fun Conversation(api: ConnectTestApi, code: String, child: Child, teacher: Teacher, back: () -> Unit) {
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { messages = withContext(Dispatchers.IO) { api.messages(code, child.id, teacher.id) } }.onFailure { error = it.message ?: "Erreur" } } }
    LaunchedEffect(Unit) { refresh() }
    PollWhileVisible(8_000L) { messages = withContext(Dispatchers.IO) { api.messages(code, child.id, teacher.id) } }
    val listState = rememberLazyListState()
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex) }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, "Retour") }
            Column { Text(teacher.name, fontWeight = FontWeight.Bold); Text(teacher.subject, fontSize = 11.sp, color = Kaki) }
        }
        Text("5 messages maximum par jour et par compte. Réinitialisation à 00h GMT.", fontSize = 11.sp, color = Kaki)
        if (error.isNotBlank()) Text(error, color = Red, fontSize = 12.sp)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState, contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(messages) { m -> Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.senderRole == "parent") Arrangement.End else Arrangement.Start) { Card(shape = RoundedCornerShape(16.dp)) { Column(Modifier.padding(12.dp)) { Text(m.body); Text(m.createdAt, fontSize = 9.sp, color = Kaki) } } } }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(text, { text = it }, Modifier.weight(1f), placeholder = { Text("Votre message...") }, maxLines = 4)
            IconButton(onClick = {
                if (text.isNotBlank()) {
                    val sent = text.trim(); text = ""; error = ""
                    scope.launch { runCatching { withContext(Dispatchers.IO) { api.sendParentMessage(code, child.id, teacher.id, sent) }; refresh() }.onFailure { error = it.message ?: "Envoi impossible." } }
                }
            }) { Icon(Icons.Default.Send, "Envoyer", tint = DarkGreen) }
        }
    }
}

@Composable
private fun TeacherDirectionMessagesScreen(api: ConnectTestApi, code: String, back: () -> Unit) {
    var items by remember { mutableStateOf<List<Announcement>>(emptyList()) }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { items = withContext(Dispatchers.IO) { api.teacherAnnouncements(code) } } } }
    LaunchedEffect(Unit) { refresh() }
    PollWhileVisible(20_000L) { items = withContext(Dispatchers.IO) { api.teacherAnnouncements(code) } }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, "Retour") }
            Text("Message de la Direction", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        }
        Spacer(Modifier.height(8.dp))
        Text("Messages envoyés par la Direction à cet enseignant.", color = Kaki, fontSize = 12.sp)
        Spacer(Modifier.height(12.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(items) { n ->
                val c = when (n.importance) { "urgent", "rouge" -> Red; else -> YellowGreen }
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                    Column(Modifier.padding(16.dp)) {
                        Text(n.title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                        Text(n.createdAt, color = Kaki, fontSize = 11.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(n.body)
                        Spacer(Modifier.height(8.dp))
                        Box(Modifier.fillMaxWidth().height(4.dp).background(c, RoundedCornerShape(4.dp)))
                    }
                }
            }
        }
        if (items.isEmpty()) Text("Aucun message de la Direction.", color = Kaki)
    }
}

@Composable
private fun TeacherHome(api: ConnectTestApi, code: String, teacherName: String, onExit: () -> Unit, logout: () -> Unit) {
    var assignments by remember { mutableStateOf<List<TeacherClass>>(emptyList()) }
    var selectedAssignment by remember { mutableStateOf<TeacherClass?>(null) }
    var term by remember { mutableStateOf("1er trimestre") }
    var students by remember { mutableStateOf<List<Student>>(emptyList()) }
    var selectedStudent by remember { mutableStateOf<Student?>(null) }
    var noteType by remember { mutableStateOf("") }
    var noteTitle by remember { mutableStateOf("") }
    var noteValue by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var step by remember { mutableStateOf("home") }
    var classStats by remember { mutableStateOf<List<ClassStat>>(emptyList()) }
    var rankings by remember { mutableStateOf<List<StudentRanking>>(emptyList()) }
    var selectedStatClass by remember { mutableStateOf<ClassStat?>(null) }
    var conversations by remember { mutableStateOf<List<TeacherConversation>>(emptyList()) }
    var selectedConversation by remember { mutableStateOf<TeacherConversation?>(null) }
    val scope = rememberCoroutineScope()

    val teacherLevel = selectedAssignment?.level ?: "college"
    SideEffect { Palette.level = teacherLevel }
    DisposableEffect(Unit) { onDispose { Palette.level = "college" } }
    BackHandler(enabled = true) {
        when (step) {
            "home" -> onExit()
            "assignments" -> step = "home"
            "noteTypes" -> { selectedAssignment = null; step = "assignments" }
            "students" -> { selectedStudent = null; step = "noteTypes" }
            "entry" -> { selectedStudent = null; step = "students" }
            "statistics" -> { selectedStatClass = null; rankings = emptyList(); step = "home" }
            "ranking" -> { selectedStatClass = null; rankings = emptyList(); step = "statistics" }
            "messages" -> { selectedConversation = null; step = "home" }
            "conversation" -> { selectedConversation = null; step = "messages" }
            "direction" -> step = "home"
        }
    }

    LaunchedEffect(Unit) { runCatching { assignments = withContext(Dispatchers.IO) { api.teacherClasses(code) } } }
    PollWhileVisible(15_000L) { if (step == "messages") conversations = withContext(Dispatchers.IO) { api.teacherConversations(code) } }
    val visibleStudents = students.filter { it.name.contains(search.trim(), ignoreCase = true) }

    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Header("ESPACE ENSEIGNANT", "", logout)
        when (step) {
            "home" -> {
                Text("Bienvenu Mr $teacherName", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(18.dp))
                ParentAction("Mes classes et matières", Icons.Default.Class) { step = "assignments" }
                ParentAction("Statistique", Icons.Default.BarChart) {
                    step = "statistics"
                    scope.launch { classStats = withContext(Dispatchers.IO) { api.teacherClassStats(code, term) } }
                }
                ParentAction("Messagerie", Icons.Default.Mail) {
                    step = "messages"
                    scope.launch { conversations = withContext(Dispatchers.IO) { api.teacherConversations(code) } }
                }
                ParentAction("Message de la Direction", Icons.Default.Campaign) { step = "direction" }
            }
            "assignments" -> {
                TextButton(onClick = { step = "home" }) { Text("← Tableau de bord") }
                Text("Saisie de Notes", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(10.dp))
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(assignments) { a -> ParentAction("${a.className} • ${a.subjectName}${if (a.homeroom) " • Titulaire" else ""}", Icons.Default.Class) { selectedAssignment = a; noteType = ""; step = "noteTypes" } } }
            }
            "noteTypes" -> {
                TextButton(onClick = { selectedAssignment = null; step = "assignments" }) { Text("← Mes classes") }
                Text("${selectedAssignment!!.className} — ${selectedAssignment!!.subjectName}", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(10.dp)); Text("1. Choisissez d'abord le type de note", fontWeight = FontWeight.Bold); Spacer(Modifier.height(8.dp))
                listOf("devoir" to "Devoir", "moyenne_classe" to "Moyenne de classe", "composition" to "Composition").forEach { (value, label) ->
                    ParentAction(label, if (value == "composition") Icons.Default.Assignment else Icons.Default.EditNote) {
                        noteType = value; search = ""; selectedStudent = null
                        scope.launch { students = withContext(Dispatchers.IO) { api.teacherStudents(code, selectedAssignment!!.classId) } }
                        step = "students"
                    }
                }
            }
            "students" -> {
                TextButton(onClick = { step = "noteTypes" }) { Text("← Type de note") }
                Text("${selectedAssignment!!.className} — ${selectedAssignment!!.subjectName}", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("Type : ${if (noteType == "moyenne_classe") "Moyenne de classe" else if (noteType == "composition") "Composition" else "Devoir"}", color = Kaki)
                Spacer(Modifier.height(8.dp)); TermTabs(term) { term = it }
                Spacer(Modifier.height(8.dp)); OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), label = { Text("Rechercher un élève") }, singleLine = true)
                Spacer(Modifier.height(10.dp)); Text("2. Liste alphabétique des élèves", fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp)); LazyColumn(verticalArrangement = Arrangement.spacedBy(7.dp)) { items(visibleStudents) { s -> Card(Modifier.fillMaxWidth().clickable { selectedStudent = s; noteValue = ""; noteTitle = ""; message = ""; step = "entry" }, shape = RoundedCornerShape(14.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Text(s.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Icon(Icons.Default.ChevronRight, null) } } } }
            }
            "entry" -> {
                val currentIndex = students.indexOfFirst { it.id == selectedStudent!!.id }
                val isLast = currentIndex >= students.lastIndex
                TextButton(onClick = { selectedStudent = null; step = "students" }) { Text("← Liste des élèves") }
                Text(selectedStudent!!.name, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("${selectedAssignment!!.subjectName} • ${if (noteType == "moyenne_classe") "Moyenne de classe" else if (noteType == "composition") "Composition" else "Devoir"} • $term", color = Kaki)
                Spacer(Modifier.height(20.dp))
                if (noteType == "devoir") { OutlinedTextField(noteTitle, { noteTitle = it }, label = { Text("Libellé du devoir") }, modifier = Modifier.fillMaxWidth()); Spacer(Modifier.height(10.dp)) }
                OutlinedTextField(value = noteValue, onValueChange = { raw -> val normalized = raw.replace(',', '.'); if (normalized.matches(Regex("^\\d{0,2}(\\.\\d{0,2})?$"))) noteValue = normalized }, label = { Text("Note sur 20") }, placeholder = { Text("Ex. 8,75 ou 19,5") }, supportingText = { Text("Jusqu'à 2 chiffres après la virgule") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                Spacer(Modifier.height(12.dp))
                Button(onClick = {
                    val v = noteValue.replace(',','.').toDoubleOrNull()
                    if (v != null && v in 0.0..20.0) {
                        scope.launch { try { withContext(Dispatchers.IO) { api.saveNote(code, selectedStudent!!.id, selectedAssignment!!.assignmentId, term, noteType, v, noteTitle.ifBlank { null }) }; message = "Note enregistrée."; noteValue = ""; noteTitle = ""; val next = students.getOrNull(currentIndex + 1); if (next != null) selectedStudent = next else step = "students" } catch (e: Exception) { message = "Erreur : ${e.message?.take(100) ?: "enregistrement impossible"}" } }
                    } else message = "Entrez une note entre 0 et 20."
                }, modifier = Modifier.fillMaxWidth().height(54.dp)) { Text(if (isLast) "ENREGISTRER ET TERMINER" else "ENREGISTRER ET SUIVRE →", fontWeight = FontWeight.Bold) }
                if (message.isNotBlank()) { Spacer(Modifier.height(10.dp)); Text(message, color = if (message.startsWith("Erreur")) Red else DarkGreen) }
                Spacer(Modifier.height(18.dp)); Text("Élève ${currentIndex + 1} / ${students.size}", color = Kaki, fontSize = 12.sp)
            }
            "statistics" -> {
                TextButton(onClick = { step = "home" }) { Text("← Tableau de bord") }
                Text("Statistique", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(8.dp)); TermTabs(term) { newTerm -> term = newTerm; scope.launch { classStats = withContext(Dispatchers.IO) { api.teacherClassStats(code, term) } } }
                Spacer(Modifier.height(10.dp)); Text("Classes et effectifs", fontWeight = FontWeight.Bold)
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(classStats) { c -> ParentAction("${c.className}  •  ${c.effectif} élève${if (c.effectif > 1) "s" else ""}", Icons.Default.Groups) { selectedStatClass = c; scope.launch { rankings = withContext(Dispatchers.IO) { api.teacherRankings(code, c.classId, term) }; step = "ranking" } } } }
            }
            "ranking" -> {
                TextButton(onClick = { selectedStatClass = null; rankings = emptyList(); step = "statistics" }) { Text("← Statistique") }
                Text("${selectedStatClass!!.className} — Classement", fontSize = 23.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("${term} • moyenne générale uniquement (devoirs exclus)", color = Kaki, fontSize = 12.sp)
                Spacer(Modifier.height(10.dp))
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) { items(rankings) { r -> Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) { Row(Modifier.padding(15.dp), verticalAlignment = Alignment.CenterVertically) { Text("${rankings.indexOf(r) + 1}", fontSize = 20.sp, fontWeight = FontWeight.Black, color = DarkGreen, modifier = Modifier.width(36.dp)); Text(r.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Text(r.generalAverage?.let { String.format(Locale.FRANCE, "%.2f / 20", it) } ?: "—", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen) } } } }
            }
            "messages" -> {
                TextButton(onClick = { step = "home" }) { Text("← Tableau de bord") }
                Text("Messagerie", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("5 messages maximum par jour et par compte. Réinitialisation à 00h GMT.", fontSize = 11.sp, color = Kaki)
                Spacer(Modifier.height(10.dp))
                LazyColumn(verticalArrangement = Arrangement.spacedBy(9.dp)) { items(conversations) { c -> ParentAction("Parent de ${c.studentName}", Icons.Default.Person) { selectedConversation = c; step = "conversation" } } }
                if (conversations.isEmpty()) Text("Aucun message reçu.", color = Kaki)
            }
            "conversation" -> selectedConversation?.let { c ->
                TeacherConversationScreen(api, code, c, { selectedConversation = null; step = "messages" })
            }
            "direction" -> TeacherDirectionMessagesScreen(api, code) { step = "home" }
        }
    }
}

@Composable
private fun TeacherConversationScreen(api: ConnectTestApi, code: String, conversation: TeacherConversation, back: () -> Unit) {
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { messages = withContext(Dispatchers.IO) { api.teacherMessages(code, conversation.studentId, conversation.parentId) } }.onFailure { error = it.message ?: "Erreur" } } }
    LaunchedEffect(Unit) { refresh() }
    PollWhileVisible(8_000L) { messages = withContext(Dispatchers.IO) { api.teacherMessages(code, conversation.studentId, conversation.parentId) } }
    val listState = rememberLazyListState()
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex) }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, "Retour") }
            Column { Text("Parent de ${conversation.studentName}", fontWeight = FontWeight.Bold); Text(conversation.parentName, fontSize = 11.sp, color = Kaki); Text(conversation.className, fontSize = 11.sp, color = Kaki) }
        }
        Text("5 messages maximum par jour et par compte. Réinitialisation à 00h GMT.", fontSize = 11.sp, color = Kaki)
        if (error.isNotBlank()) Text(error, color = Red, fontSize = 12.sp)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState, contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { items(messages) { m -> Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.senderRole == "teacher") Arrangement.End else Arrangement.Start) { Card(shape = RoundedCornerShape(16.dp)) { Column(Modifier.padding(12.dp)) { Text(m.body); Text(m.createdAt, fontSize = 9.sp, color = Kaki) } } } } }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(text, { text = it }, Modifier.weight(1f), placeholder = { Text("Votre message...") }, maxLines = 4)
            IconButton(onClick = { if (text.isNotBlank()) { val sent = text.trim(); text = ""; error = ""; scope.launch { runCatching { withContext(Dispatchers.IO) { api.sendTeacherMessage(code, conversation.studentId, conversation.parentId, sent) }; refresh() }.onFailure { error = it.message ?: "Envoi impossible." } } } }) { Icon(Icons.Default.Send, "Envoyer", tint = DarkGreen) }
        }
    }
}


// ============================================================================
// COMPLEXE SCOLAIRE SAINT JEAN PAUL II — Drapeau, frais de scolarité, cantine
// ============================================================================

/** Drapeau du Togo : 5 bandes vertes/jaunes, carré rouge avec étoile blanche. */
@Composable
private fun TogoFlag(modifier: Modifier = Modifier) {
    Canvas(modifier.clip(RoundedCornerShape(2.dp))) {
        val h = size.height / 5f
        val green = Color(0xFF006A4E)
        val yellow = Color(0xFFFFCE00)
        val red = Color(0xFFD21034)
        for (i in 0 until 5) {
            drawRect(if (i % 2 == 0) green else yellow, topLeft = Offset(0f, h * i), size = Size(size.width, h))
        }
        drawRect(red, topLeft = Offset(0f, 0f), size = Size(h * 3f, h * 3f))
        val cx = h * 1.5f
        val cy = h * 1.5f
        val outer = h * 1.0f
        val inner = outer * 0.382f
        val star = Path()
        for (k in 0 until 10) {
            val r = if (k % 2 == 0) outer else inner
            val ang = Math.toRadians(-90.0 + k * 36.0)
            val x = cx + (r * Math.cos(ang)).toFloat()
            val y = cy + (r * Math.sin(ang)).toFloat()
            if (k == 0) star.moveTo(x, y) else star.lineTo(x, y)
        }
        star.close()
        drawPath(star, Color.White)
    }
}

private fun fcfa(v: Double): String =
    String.format(Locale.FRANCE, "%,.0f", v).replace('\u202f', ' ').replace('\u00a0', ' ') + " FCFA"

private fun dayFr(iso: String): String =
    iso.split('-').let { if (it.size == 3) "${it[2]}/${it[1]}/${it[0]}" else iso }

private fun dayLabel(iso: String): String = runCatching {
    val d = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(iso)!!
    SimpleDateFormat("EEE dd/MM", Locale.FRANCE).format(d)
}.getOrDefault(iso)

private fun decodeBase64Image(b64: String): androidx.compose.ui.graphics.ImageBitmap? = runCatching {
    val bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT)
    android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
}.getOrNull()

/** Réduit la photo (1000 px max, JPEG 72 %) et la renvoie en base64 pour l'envoi. */
private fun uriToBase64(context: Context, uri: Uri): String? = runCatching {
    val resolver = context.contentResolver
    val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (bounds.outWidth / sample > 2000 || bounds.outHeight / sample > 2000) sample *= 2
    val opts = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
    var bmp: android.graphics.Bitmap = resolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, opts) }
        ?: return@runCatching null
    val rotation: Float = resolver.openInputStream(uri)?.use { stream ->
        when (android.media.ExifInterface(stream).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)) {
            6 -> 90f
            3 -> 180f
            8 -> 270f
            else -> 0f
        }
    } ?: 0f
    if (rotation != 0f) {
        val m = android.graphics.Matrix()
        m.postRotate(rotation)
        bmp = android.graphics.Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }
    val maxSide = 1000f
    val scale = minOf(1f, maxSide / maxOf(bmp.width, bmp.height).toFloat())
    if (scale < 1f) {
        bmp = android.graphics.Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
    }
    val out = java.io.ByteArrayOutputStream()
    bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 72, out)
    android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.NO_WRAP)
}.getOrNull()

@Composable
private fun Base64Photo(b64: String, modifier: Modifier = Modifier) {
    val img = remember(b64) { decodeBase64Image(b64) }
    if (img != null) {
        Image(img, contentDescription = "Photo du plat", modifier = modifier.clip(RoundedCornerShape(16.dp)), contentScale = ContentScale.Crop)
    } else {
        Box(modifier.clip(RoundedCornerShape(16.dp)).background(Beurre), Alignment.Center) { Text("Photo indisponible", color = Kaki, fontSize = 12.sp) }
    }
}

/** Parent : frais de scolarité de l'enfant (déjà payé, reste à payer, tranches). */
@Composable
private fun FeesScreen(api: ConnectTestApi, code: String, child: Child, back: () -> Unit) {
    var info by remember { mutableStateOf<FeeInfo?>(null) }
    var error by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    BackHandler { back() }
    LaunchedEffect(child.id) {
        loading = true
        runCatching { withContext(Dispatchers.IO) { api.parentFees(code, child.id) } }
            .onSuccess { info = it; error = "" }
            .onFailure { error = it.message ?: "Chargement impossible." }
        loading = false
    }
    PollWhileVisible(30_000L) { info = withContext(Dispatchers.IO) { api.parentFees(code, child.id) } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("Frais de scolarité", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        Spacer(Modifier.height(10.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (error.isNotBlank()) Text("Erreur : $error", color = Red, fontSize = 12.sp)
        val f = info
        if (f != null) {
            if (!f.defined) {
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Beurre)) {
                    Text("Le montant total des frais de ${f.className} n'est pas encore défini par la Direction.", modifier = Modifier.padding(18.dp), color = Black)
                }
                Spacer(Modifier.height(10.dp))
            }
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp)) {
                Column(Modifier.padding(20.dp)) {
                    Text("${child.name} • ${f.className}", color = Kaki, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(10.dp))
                    Text("DÉJÀ PAYÉ", color = Kaki, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text(fcfa(f.paid), color = Color(0xFF14804A), fontSize = 30.sp, fontWeight = FontWeight.Black)
                    if (f.defined) {
                        Spacer(Modifier.height(10.dp))
                        Text("RESTE À PAYER", color = Kaki, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        Text(fcfa(f.remaining), color = if (f.remaining > 0) Red else Color(0xFF14804A), fontSize = 30.sp, fontWeight = FontWeight.Black)
                        Spacer(Modifier.height(10.dp))
                        Text("Total à payer : ${fcfa(f.totalDue)}", color = Black, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.height(8.dp))
                        val frac = if (f.totalDue > 0) (f.paid / f.totalDue).toFloat().coerceIn(0f, 1f) else 0f
                        LinearProgressIndicator(progress = { frac }, modifier = Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(8.dp)), color = Accent)
                        Text("${(frac * 100).toInt()} % payé", color = Kaki, fontSize = 11.sp)
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            Text("Tranches payées (${f.payments.size})", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
            Spacer(Modifier.height(6.dp))
            if (f.payments.isEmpty()) Text("Aucun paiement enregistré pour le moment.", color = Kaki)
            f.payments.forEach { p ->
                Card(Modifier.fillMaxWidth().padding(vertical = 4.dp), shape = RoundedCornerShape(14.dp), colors = CardDefaults.cardColors(containerColor = Beurre)) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Tranche N° ${p.no}", fontWeight = FontWeight.Bold)
                            Text(dayFr(p.paidAt), color = Kaki, fontSize = 12.sp)
                        }
                        Text(fcfa(p.amount), fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                    }
                }
            }
        }
    }
}

/** Parent ou cantine : menus de la semaine, par date, avec les photos des plats. */
@Composable
private fun CanteenViewer(api: ConnectTestApi, code: String, title: String, subtitle: String, back: () -> Unit) {
    var dates by remember { mutableStateOf<List<MenuDate>>(emptyList()) }
    var selected by remember { mutableStateOf<String?>(null) }
    var day by remember { mutableStateOf<CanteenDay?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf("") }
    BackHandler { back() }
    LaunchedEffect(Unit) {
        loading = true
        runCatching { withContext(Dispatchers.IO) { api.canteenDates(code) } }
            .onSuccess { list -> dates = list; if (selected == null) selected = list.firstOrNull()?.date; error = "" }
            .onFailure { error = it.message ?: "Chargement impossible." }
        loading = false
    }
    LaunchedEffect(selected) {
        val d = selected
        if (d != null) {
            day = null
            runCatching { withContext(Dispatchers.IO) { api.canteenMenu(code, d) } }
                .onSuccess { day = it }
                .onFailure { error = it.message ?: "Chargement impossible." }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text(title, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        Text(subtitle, color = Kaki, fontSize = 13.sp)
        Spacer(Modifier.height(10.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (error.isNotBlank()) Text("Erreur : $error", color = Red, fontSize = 12.sp)
        if (!loading && dates.isEmpty() && error.isBlank()) {
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Beurre)) {
                Text("Aucun menu enregistré cette semaine. Les menus et photos sont effacés chaque dimanche à 00h GMT.", modifier = Modifier.padding(18.dp), color = Black)
            }
        }
        if (dates.isNotEmpty()) {
            Text("Choisissez une date", color = Kaki, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(dates) { d ->
                    FilterChip(selected = selected == d.date, onClick = { selected = d.date }, label = { Text(dayLabel(d.date), fontSize = 12.sp) })
                }
            }
            Spacer(Modifier.height(14.dp))
        }
        val m = day
        if (m != null) {
            if (!m.exists) {
                Text("Aucun menu pour cette date.", color = Kaki)
            } else {
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp)) {
                    Column(Modifier.padding(18.dp)) {
                        Text(dayFr(m.date), color = Kaki, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        Text(m.dishName, fontSize = 22.sp, fontWeight = FontWeight.Black, color = DarkGreen)
                        if (m.description.isNotBlank()) Text(m.description, color = Black, fontSize = 14.sp)
                        if (m.staffName.isNotBlank()) Text("Préparé par ${m.staffName}", color = Kaki, fontSize = 11.sp)
                    }
                }
                Spacer(Modifier.height(10.dp))
                if (m.photos.isEmpty()) Text("Pas de photo pour ce plat.", color = Kaki)
                m.photos.forEach { ph ->
                    Base64Photo(ph, Modifier.fillMaxWidth().height(230.dp))
                    Spacer(Modifier.height(10.dp))
                }
            }
        }
    }
}

/** Personnel de cantine : saisie du plat du jour + 2 photos (une seule fois pour toute la cantine). */
@Composable
private fun CanteenTodayScreen(api: ConnectTestApi, code: String, back: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var day by remember { mutableStateOf<CanteenDay?>(null) }
    var dish by remember { mutableStateOf("") }
    var desc by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<List<String>>(emptyList()) }
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    BackHandler { back() }

    fun reload() {
        scope.launch {
            runCatching { withContext(Dispatchers.IO) { api.canteenToday(code) } }
                .onSuccess { d ->
                    day = d
                    if (d.exists && dish.isBlank()) { dish = d.dishName; desc = d.description }
                }
                .onFailure { message = it.message?.take(200) ?: "Chargement impossible." }
        }
    }
    LaunchedEffect(Unit) { reload() }

    fun addPicked(uri: Uri) {
        scope.launch {
            val b64 = withContext(Dispatchers.IO) { uriToBase64(context, uri) }
            if (b64 == null) {
                message = "Photo illisible, réessayez."
            } else {
                val room = 2 - (day?.photos?.size ?: 0)
                pending = (pending + b64).takeLast(maxOf(room, 0))
                message = ""
            }
        }
    }
    val galleryLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri != null) addPicked(uri)
    }
    val cameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok: Boolean ->
        val uri = cameraUri
        if (ok && uri != null) addPicked(uri)
    }
    fun launchCamera() {
        val dir = java.io.File(context.cacheDir, "images").apply { mkdirs() }
        val file = java.io.File(dir, "plat_${System.currentTimeMillis()}.jpg")
        val uri = androidx.core.content.FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        cameraUri = uri
        cameraLauncher.launch(uri)
    }

    val d = day
    val savedPhotos = d?.photos ?: emptyList()
    val locked = d?.locked == true
    val room = 2 - savedPhotos.size

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("Menu du jour", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        if (d != null) Text(dayFr(d.date) + " (heure GMT)", color = Kaki, fontSize = 12.sp)
        Spacer(Modifier.height(10.dp))
        if (d == null) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (locked) {
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Beurre)) {
                Column(Modifier.padding(16.dp)) {
                    Text("Plat du jour complet", fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                    Text("Les 2 photos ont déjà été ajoutées${if (!d?.staffName.isNullOrBlank()) " (menu de ${d?.staffName})" else ""}. Vous pouvez les consulter.", color = Black, fontSize = 13.sp)
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(d?.dishName ?: "", fontSize = 22.sp, fontWeight = FontWeight.Black, color = DarkGreen)
            if (!d?.description.isNullOrBlank()) Text(d?.description ?: "", color = Black)
            Spacer(Modifier.height(8.dp))
        } else if (d != null) {
            OutlinedTextField(dish, { dish = it }, Modifier.fillMaxWidth(), label = { Text("Nom du plat du jour") }, singleLine = true, shape = RoundedCornerShape(14.dp))
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(desc, { desc = it }, Modifier.fillMaxWidth(), label = { Text("Détails (facultatif)") }, maxLines = 3, shape = RoundedCornerShape(14.dp))
            Spacer(Modifier.height(12.dp))
            Text("Photos du plat (2 maximum pour toute la cantine) — ${savedPhotos.size} déjà ajoutée${if (savedPhotos.size > 1) "s" else ""}", color = Kaki, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
        }
        savedPhotos.forEach { ph ->
            Base64Photo(ph, Modifier.fillMaxWidth().height(200.dp))
            Spacer(Modifier.height(8.dp))
        }
        if (!locked && d != null) {
            pending.forEachIndexed { idx, ph ->
                Box(Modifier.fillMaxWidth()) {
                    Base64Photo(ph, Modifier.fillMaxWidth().height(200.dp))
                    TextButton(onClick = { pending = pending.filterIndexed { i, _ -> i != idx } }, modifier = Modifier.align(Alignment.TopEnd)) { Text("Retirer", color = Red, fontWeight = FontWeight.Bold) }
                }
                Spacer(Modifier.height(8.dp))
            }
            if (pending.size < room) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { launchCamera() }, modifier = Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(14.dp)) {
                        Icon(Icons.Default.PhotoCamera, null); Spacer(Modifier.width(6.dp)); Text("Prendre une photo", fontSize = 12.sp)
                    }
                    OutlinedButton(onClick = { galleryLauncher.launch("image/*") }, modifier = Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(14.dp)) {
                        Icon(Icons.Default.PhotoLibrary, null); Spacer(Modifier.width(6.dp)); Text("Galerie", fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
            Button(
                onClick = {
                    if (dish.isBlank()) {
                        message = "Saisissez le nom du plat."
                    } else {
                        scope.launch {
                            busy = true; message = ""
                            try {
                                val toSend = pending
                                withContext(Dispatchers.IO) {
                                    api.canteenSaveMenu(code, dish.trim(), desc.trim())
                                    toSend.forEach { api.canteenAddPhoto(code, it) }
                                }
                                pending = emptyList()
                                message = "Plat du jour enregistré."
                            } catch (e: Exception) {
                                pending = emptyList()
                                message = "Erreur : " + (e.message?.take(200) ?: "enregistrement impossible")
                            } finally {
                                busy = false
                                reload()
                            }
                        }
                    }
                },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth().height(54.dp),
                shape = RoundedCornerShape(16.dp)
            ) { Text(if (busy) "Envoi en cours..." else "ENREGISTRER LE PLAT DU JOUR", fontWeight = FontWeight.Bold) }
        }
        if (message.isNotBlank()) {
            Spacer(Modifier.height(10.dp))
            Text(message, color = if (message.startsWith("Erreur")) Red else DarkGreen, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun CanteenDirectionScreen(api: ConnectTestApi, code: String, back: () -> Unit) {
    var items by remember { mutableStateOf<List<Announcement>>(emptyList()) }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { items = withContext(Dispatchers.IO) { api.canteenAnnouncements(code) } } } }
    LaunchedEffect(Unit) { refresh() }
    PollWhileVisible(20_000L) { items = withContext(Dispatchers.IO) { api.canteenAnnouncements(code) } }
    Column(Modifier.fillMaxSize()) {
        Text("Message de la Direction", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        Spacer(Modifier.height(12.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(items) { n ->
                val c = if (n.importance == "urgent") Red else Navy
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                    Column(Modifier.padding(16.dp)) {
                        Text(n.title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                        Text(n.createdAt, color = Kaki, fontSize = 11.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(n.body)
                        Spacer(Modifier.height(8.dp))
                        Box(Modifier.fillMaxWidth().height(4.dp).background(c, RoundedCornerShape(4.dp)))
                    }
                }
            }
        }
        if (items.isEmpty()) Text("Aucun message de la Direction.", color = Kaki)
    }
}

@Composable
private fun CanteenHome(api: ConnectTestApi, code: String, name: String, onExit: () -> Unit, logout: () -> Unit) {
    var step by remember { mutableStateOf("home") }
    BackHandler { if (step == "home") onExit() else step = "home" }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Header("ESPACE CANTINE", "", logout)
        when (step) {
            "home" -> {
                Text("Bienvenue $name", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(18.dp))
                ParentAction("Menu du jour (nom + 2 photos)", Icons.Default.Restaurant) { step = "today" }
                ParentAction("Menus de la semaine", Icons.Default.PhotoLibrary) { step = "week" }
                ParentAction("Message de la Direction", Icons.Default.Campaign) { step = "direction" }
            }
            "today" -> CanteenTodayScreen(api, code) { step = "home" }
            "week" -> CanteenViewer(api, code, "Menus de la semaine", "Effacement automatique chaque dimanche à 00h GMT") { step = "home" }
            "direction" -> CanteenDirectionScreen(api, code) { step = "home" }
        }
    }
}
