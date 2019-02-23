
// see http://logging.apache.org/log4j/1.2/manual.html
import java.util.UUID;
import org.apache.log4j.Logger;
import org.apache.log4j.MDC;

public class Example {
    final static Logger log = Logger.getLogger(Example.class);

    public static void main(String[] args) throws Exception {
        String application = "java-log4j-syslog/1.0";

        MDC.put("application", application);

        log.info("Begin");

        String traceId = UUID.randomUUID().toString().replace("-", "");

        MDC.put("traceId", traceId);
        try {
            int a = 10;
            int b = 0;

            try {
                log.debug("Dividing " + a + " by " + b);
                System.out.println(a / b);
            } catch (Exception ex) {
                log.error("Something went wrong with the division", ex);
            }
        } finally {
            MDC.remove("traceId");
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
