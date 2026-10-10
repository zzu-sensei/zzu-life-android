package cn.edu.zzu.life;

import com.chaquo.python.PyObject;
import com.chaquo.python.Python;

import org.json.JSONObject;

final class PythonGateway {
    private PythonGateway() {}

    static JSONObject call(String method, Object... args) throws Exception {
        PyObject module = Python.getInstance().getModule("mobile_bridge");
        String raw = module.callAttr(method, args).toString();
        return new JSONObject(raw);
    }

    static JSONObject callWithSession(ContextSession session, String method, Object... extra)
        throws Exception {
        Object[] args = new Object[3 + extra.length];
        args[0] = session.account;
        args[1] = session.userToken;
        args[2] = session.refreshToken;
        System.arraycopy(extra, 0, args, 3, extra.length);
        return call(method, args);
    }

    static final class ContextSession {
        final String account;
        final String userToken;
        final String refreshToken;

        ContextSession(String[] values) {
            account = values[0];
            userToken = values[1];
            refreshToken = values[2];
        }
    }
}
