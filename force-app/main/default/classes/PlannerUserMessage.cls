/**
 * Turns Apex/DML/Aura exceptions into short messages safe for PWA REST and LWC toasts.
 */
public with sharing class PlannerUserMessage {
  public static AuraHandledException aura(String message) {
    String clean = sanitize(message);
    AuraHandledException ahe = new AuraHandledException(clean);
    ahe.setMessage(clean);
    return ahe;
  }

  public static String fromException(Exception e) {
    if (e == null) {
      return 'Something went wrong. Please try again.';
    }
    if (e instanceof DmlException) {
      DmlException dml = (DmlException) e;
      if (dml.getNumDml() > 0) {
        return sanitize(dml.getDmlMessage(0));
      }
    }
    return sanitize(e.getMessage());
  }

  public static String sanitize(String raw) {
    if (String.isBlank(raw)) {
      return 'Something went wrong. Please try again.';
    }
    String message = raw.trim();
    if (message.equalsIgnoreCase('Script-thrown exception')) {
      return 'Something went wrong. Please try again.';
    }
    message = message.replace('FIELD_CUSTOM_VALIDATION_EXCEPTION, ', '');
    message = message.replace('FIELD_CUSTOM_VALIDATION_EXCEPTION:', '');
    message = message.replace('REQUIRED_FIELD_MISSING, ', '');
    message = message.replace('REQUIRED_FIELD_MISSING:', '');
    message = message.replace('DUPLICATE_VALUE, ', '');
    message = message.replace('STRING_TOO_LONG, ', '');
    message = message.replace('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST, ', '');
    Integer firstColon = message.indexOf(':');
    if (firstColon > 0 && message.substring(0, firstColon).isAllUpperCase()) {
      message = message.substring(firstColon + 1).trim();
    }
    if (message.endsWith(': []') || message.endsWith(':[]')) {
      message = message.substring(0, message.lastIndexOf(':')).trim();
    }
    if (message.length() > 400) {
      message = message.substring(0, 397) + '...';
    }
    return String.isBlank(message) ? 'Something went wrong. Please try again.' : message;
  }
}