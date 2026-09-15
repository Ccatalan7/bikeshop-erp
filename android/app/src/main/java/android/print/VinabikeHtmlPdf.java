package android.print;

import android.content.Context;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Runs a {@link PrintDocumentAdapter} to a temporary file and always answers.
 *
 * <p>Lives in {@code android.print} because the layout and write callbacks have
 * package private constructors. The plugin helper this replaces overrides only
 * {@code onLayoutFinished} and {@code onWriteFinished}, so a conversion that
 * fails or is cancelled never calls back at all and the caller waits forever
 * (the owner's invoice, Android, 2026-09-04). It also reads the finished file
 * with a single {@code read()}, which is allowed to return a short count on a
 * large PDF; this one loops until the file is consumed.
 */
public final class VinabikeHtmlPdf {
    public interface Result {
        void onSuccess(byte[] document);

        void onError(String message);
    }

    private VinabikeHtmlPdf() {
    }

    public static void print(
            final Context context,
            final PrintDocumentAdapter adapter,
            final PrintAttributes attributes,
            final Result result) {
        final boolean[] answered = {false};
        adapter.onLayout(
                null,
                attributes,
                new CancellationSignal(),
                new PrintDocumentAdapter.LayoutResultCallback() {
                    @Override
                    public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
                        writeDocument(context, adapter, result, answered);
                    }

                    @Override
                    public void onLayoutFailed(CharSequence error) {
                        answerError(result, answered,
                                error == null ? "Layout failed" : error.toString());
                    }

                    @Override
                    public void onLayoutCancelled() {
                        answerError(result, answered, "Layout cancelled");
                    }
                },
                null);
    }

    private static void writeDocument(
            final Context context,
            final PrintDocumentAdapter adapter,
            final Result result,
            final boolean[] answered) {
        final File output;
        try {
            output = File.createTempFile("vinabike-invoice", ".pdf", context.getCacheDir());
        } catch (IOException error) {
            answerError(result, answered, "Cannot create the temporary PDF: " + error.getMessage());
            return;
        }

        try {
            adapter.onWrite(
                    new PageRange[] {PageRange.ALL_PAGES},
                    ParcelFileDescriptor.open(output, ParcelFileDescriptor.MODE_READ_WRITE),
                    new CancellationSignal(),
                    new PrintDocumentAdapter.WriteResultCallback() {
                        @Override
                        public void onWriteFinished(PageRange[] pages) {
                            try {
                                if (pages == null || pages.length == 0) {
                                    answerError(result, answered, "No page was produced");
                                    return;
                                }
                                answerSuccess(result, answered, readFile(output));
                            } catch (IOException error) {
                                answerError(result, answered,
                                        "Cannot read the produced PDF: " + error.getMessage());
                            } finally {
                                //noinspection ResultOfMethodCallIgnored
                                output.delete();
                            }
                        }

                        @Override
                        public void onWriteFailed(CharSequence error) {
                            //noinspection ResultOfMethodCallIgnored
                            output.delete();
                            answerError(result, answered,
                                    error == null ? "Write failed" : error.toString());
                        }

                        @Override
                        public void onWriteCancelled() {
                            //noinspection ResultOfMethodCallIgnored
                            output.delete();
                            answerError(result, answered, "Write cancelled");
                        }
                    });
        } catch (Exception error) {
            //noinspection ResultOfMethodCallIgnored
            output.delete();
            answerError(result, answered, "Cannot write the PDF: " + error.getMessage());
        }
    }

    private static void answerSuccess(Result result, boolean[] answered, byte[] document) {
        if (answered[0]) {
            return;
        }
        answered[0] = true;
        result.onSuccess(document);
    }

    private static void answerError(Result result, boolean[] answered, String message) {
        if (answered[0]) {
            return;
        }
        answered[0] = true;
        result.onError(message);
    }

    private static byte[] readFile(File file) throws IOException {
        byte[] buffer = new byte[(int) file.length()];
        try (InputStream stream = new FileInputStream(file)) {
            int read = 0;
            while (read < buffer.length) {
                int count = stream.read(buffer, read, buffer.length - read);
                if (count == -1) {
                    break;
                }
                read += count;
            }
        }
        return buffer;
    }
}
