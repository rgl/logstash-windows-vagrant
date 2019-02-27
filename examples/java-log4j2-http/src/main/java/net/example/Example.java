// see https://logging.apache.org/log4j/2.x/manual/usage.html
// see https://logging.apache.org/log4j/2.x/manual/thread-context.html

package net.example;

import java.util.UUID;
import org.apache.logging.log4j.CloseableThreadContext;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.ThreadContext;

public class Example {
    final static Logger log = LogManager.getLogger(Example.class);

    public static void main(String[] args) throws Exception {
        log.info("Begin");

        String traceId = UUID.randomUUID().toString().replace("-", "");

        try (final CloseableThreadContext.Instance ctc = CloseableThreadContext.put("traceId", traceId)) {
            int a = 10;
            int b = 0;

            try {
                log.debug("Dividing {} by {}", a, b);
                System.out.println(a / b);
            } catch (Exception ex) {
                log.error("Something went wrong with the division", ex);
            }
        }

        log.info(getLongMessage("long message ", 2*1024));

        log.info("End");
    }

    private static String getLongMessage(String prefix, int width) {
        StringBuffer buffer = new StringBuffer(width);
        buffer.append(prefix);
        for (int i = 0; i < width-prefix.length(); i++) {
            buffer.append(i%10);
        }
        return buffer.toString();
    }
}
