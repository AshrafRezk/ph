/**
 * Builds the exception to throw for a user-facing validation failure.
 *
 * `new AuraHandledException(...)` raises an uncatchable System.LimitException ("Can only throw this
 * exception type from VisualForce or Aura context") when the code runs inside an Apex REST request,
 * which 500s the whole request. The offline PWA outbox (PlannerMobileRestService /outbox) calls the same
 * services as Lightning, so those services throw through this factory: Lightning still gets an
 * AuraHandledException (with a readable message), REST gets a plain exception that the outbox records
 * against the single failing action.
 */
public with sharing class RestSafeError {
  public class RestException extends Exception {}

  @TestVisible
  private static Boolean forceRestForTest = false;

  public static Exception make(String message) {
    if (forceRestForTest || Request.getCurrent().getQuiddity() == Quiddity.REST) {
      return new RestException(message);
    }
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
