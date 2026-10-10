package cn.edu.zzu.life;

import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;

import java.io.FileOutputStream;

final class RawPdfPrintAdapter extends PrintDocumentAdapter {
    private final String name;
    private final byte[] content;

    RawPdfPrintAdapter(String name, byte[] content) {
        this.name = name;
        this.content = content;
    }

    @Override
    public void onLayout(
        PrintAttributes oldAttributes,
        PrintAttributes newAttributes,
        CancellationSignal cancellationSignal,
        LayoutResultCallback callback,
        Bundle extras
    ) {
        if (cancellationSignal.isCanceled()) {
            callback.onLayoutCancelled();
            return;
        }
        callback.onLayoutFinished(
            new PrintDocumentInfo.Builder(name + ".pdf")
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(PrintDocumentInfo.PAGE_COUNT_UNKNOWN)
                .build(),
            true
        );
    }

    @Override
    public void onWrite(
        PageRange[] pages,
        ParcelFileDescriptor destination,
        CancellationSignal cancellationSignal,
        WriteResultCallback callback
    ) {
        new Thread(() -> {
            try (FileOutputStream output = new FileOutputStream(destination.getFileDescriptor())) {
                if (cancellationSignal.isCanceled()) {
                    callback.onWriteCancelled();
                    return;
                }
                output.write(content);
                output.flush();
                callback.onWriteFinished(new PageRange[] {PageRange.ALL_PAGES});
            } catch (Exception error) {
                callback.onWriteFailed(error.getMessage());
            }
        }, "zzu-pdf-print").start();
    }
}
