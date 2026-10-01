/** Loads GenomicsDB's native library from the jar on the class path and prints its version. */
public class SmokeLoadNativeLib {
  public static void main(String[] args) {
    if (!org.genomicsdb.GenomicsDBLibLoader.loadLibrary()) {
      throw new IllegalStateException("GenomicsDB native library did not load");
    }
    System.out.println("GenomicsDB native library " + org.genomicsdb.GenomicsDBUtils.nativeLibraryVersion());
  }
}
