package cn.edu.zzu.life;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Map;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * AI 助手配置与最近对话的本机存储。
 *
 * API Key 使用 AndroidKeyStore AES-GCM 硬件加密存储，并与学校 CAS 会话隔离：
 * 退出学校账号仅清理校园问答记录，不会清空用户自己配置的 API 密钥与接口地址。
 */
final class AiConfigStore {
    private static final String PREFS = "ai_config";
    private static final String KEY_ALIAS = "zzu_life_ai_key";
    private static final String HISTORY_FILE = "ai_chat_history.json";
    private static final int MAX_HISTORY = 60;

    private static final String BASE_URL = "base_url";
    private static final String API_KEY_ENC = "api_key_enc";
    private static final String MODEL = "model";
    private static final String SYSTEM_PROMPT = "system_prompt";
    private static final String TEMPERATURE = "temperature";
    private static final String TOOLS_ENABLED = "tools_enabled";

    private AiConfigStore() {}

    static synchronized JSONObject loadConfig(Context context) throws Exception {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String baseUrl = prefs.getString(BASE_URL, "");
        String model = prefs.getString(MODEL, "");
        String systemPrompt = prefs.getString(SYSTEM_PROMPT, "");
        double temperature = Double.longBitsToDouble(
            prefs.getLong(TEMPERATURE, Double.doubleToRawLongBits(0.7))
        );
        if (Double.isNaN(temperature) || temperature < 0.0 || temperature > 2.0) {
            temperature = 0.7;
        }
        boolean toolsEnabled = prefs.getBoolean(TOOLS_ENABLED, true);
        String apiKey = decryptSafe(prefs, prefs.getString(API_KEY_ENC, null));

        JSONObject payload = new JSONObject();
        payload.put("ok", true);
        payload.put("base_url", baseUrl == null ? "" : baseUrl);
        payload.put("api_key", apiKey == null ? "" : apiKey);
        payload.put("model", model == null ? "" : model);
        payload.put("system_prompt", systemPrompt == null ? "" : systemPrompt);
        payload.put("temperature", temperature);
        payload.put("tools_enabled", toolsEnabled);
        payload.put(
            "configured",
            baseUrl != null && !baseUrl.trim().isEmpty() && model != null && !model.trim().isEmpty()
        );
        return payload;
    }

    static synchronized void saveConfig(Context context, Map<String, Object> values)
        throws Exception {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();
        if (values != null) {
            if (values.containsKey(BASE_URL)) {
                editor.putString(BASE_URL, stringValue(values.get(BASE_URL)));
            }
            if (values.containsKey(MODEL)) {
                editor.putString(MODEL, stringValue(values.get(MODEL)));
            }
            if (values.containsKey(SYSTEM_PROMPT)) {
                editor.putString(SYSTEM_PROMPT, stringValue(values.get(SYSTEM_PROMPT)));
            }
            if (values.containsKey(TEMPERATURE)) {
                double temp = numberValue(values.get(TEMPERATURE), 0.7);
                temp = Math.max(0.0, Math.min(2.0, temp));
                editor.putLong(TEMPERATURE, Double.doubleToRawLongBits(temp));
            }
            if (values.containsKey(TOOLS_ENABLED)) {
                editor.putBoolean(TOOLS_ENABLED, boolValue(values.get(TOOLS_ENABLED)));
            }
            if (values.containsKey("api_key")) {
                String rawKey = stringValue(values.get("api_key"));
                if (rawKey.isEmpty()) {
                    editor.remove(API_KEY_ENC);
                } else {
                    editor.putString(API_KEY_ENC, encrypt(rawKey));
                }
            }
        }
        editor.apply();
    }

    static synchronized JSONObject loadHistory(Context context) throws Exception {
        JSONObject payload = new JSONObject();
        payload.put("ok", true);
        File file = new File(context.getFilesDir(), HISTORY_FILE);
        if (!file.exists()) {
            payload.put("messages", new JSONArray());
            return payload;
        }
        try (FileInputStream in = new FileInputStream(file)) {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int n;
            while ((n = in.read(chunk)) != -1) {
                buffer.write(chunk, 0, n);
            }
            String raw = new String(buffer.toByteArray(), StandardCharsets.UTF_8);
            if (raw.isEmpty()) {
                payload.put("messages", new JSONArray());
                return payload;
            }
            JSONArray array = new JSONArray(raw);
            payload.put("messages", trimHistory(array));
            return payload;
        } catch (Exception ignored) {
            payload.put("messages", new JSONArray());
            return payload;
        }
    }

    static synchronized void saveHistory(Context context, String messagesJson) throws Exception {
        JSONArray incoming = (messagesJson == null || messagesJson.trim().isEmpty())
            ? new JSONArray()
            : new JSONArray(messagesJson);
        JSONArray trimmed = trimHistory(incoming);
        File file = new File(context.getFilesDir(), HISTORY_FILE);
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(trimmed.toString().getBytes(StandardCharsets.UTF_8));
            out.flush();
        }
    }

    static synchronized void clearHistory(Context context) {
        File file = new File(context.getFilesDir(), HISTORY_FILE);
        if (file.exists()) {
            //noinspection ResultOfMethodCallIgnored
            file.delete();
        }
    }

    private static JSONArray trimHistory(JSONArray array) {
        if (array.length() <= MAX_HISTORY) return array;
        JSONArray result = new JSONArray();
        int start = array.length() - MAX_HISTORY;
        for (int i = start; i < array.length(); i++) {
            Object item = array.opt(i);
            if (item != null) result.put(item);
        }
        return result;
    }

    private static SecretKey getKey() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (store.containsAlias(KEY_ALIAS)) {
            return (SecretKey) store.getKey(KEY_ALIAS, null);
        }
        KeyGenerator generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        );
        generator.init(new KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .build());
        return generator.generateKey();
    }

    private static String encrypt(String value) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, getKey());
        byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
        byte[] iv = cipher.getIV();
        byte[] output = new byte[iv.length + encrypted.length];
        System.arraycopy(iv, 0, output, 0, iv.length);
        System.arraycopy(encrypted, 0, output, iv.length, encrypted.length);
        return Base64.encodeToString(output, Base64.NO_WRAP);
    }

    private static String decryptSafe(SharedPreferences prefs, String value) {
        if (value == null || value.isEmpty()) return "";
        try {
            byte[] input = Base64.decode(value, Base64.NO_WRAP);
            if (input.length <= 12) return "";
            byte[] iv = new byte[12];
            byte[] encrypted = new byte[input.length - iv.length];
            System.arraycopy(input, 0, iv, 0, iv.length);
            System.arraycopy(input, iv.length, encrypted, 0, encrypted.length);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, getKey(), new GCMParameterSpec(128, iv));
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            prefs.edit().remove(API_KEY_ENC).apply();
            return "";
        }
    }

    private static String stringValue(Object value) {
        return value == null ? "" : String.valueOf(value).trim();
    }

    private static boolean boolValue(Object value) {
        return value instanceof Boolean
            ? (Boolean) value
            : Boolean.parseBoolean(String.valueOf(value));
    }

    private static double numberValue(Object value, double fallback) {
        if (value instanceof Number) return ((Number) value).doubleValue();
        try {
            return Double.parseDouble(String.valueOf(value));
        } catch (Exception ignored) {
            return fallback;
        }
    }
}
