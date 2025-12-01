#!/bin/bash
################################################################################
# Multi-Report-OMV
# Email Notification Module
# Delivers notifications via email using mail/sendmail
################################################################################
#
# Table of Contents:
# 1. Configuration
# 2. Email Validation
# 3. Email Sending
# 4. Module Registration
#
################################################################################

################################################################################
# 1. CONFIGURATION
################################################################################

# Detect script location
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

################################################################################
# 2. EMAIL VALIDATION
################################################################################

# Validate email address format
validate_email() {
    local email="$1"
    
    if [ -z "$email" ]; then
        return 1
    fi
    
    # Basic email validation (not RFC-compliant, but good enough)
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    
    return 1
}

# Check if mail command is available
check_mail_command() {
    if ! command -v mail &>/dev/null; then
        log_error "mail command not found. Please install mailutils or mailx"
        log_error "  Debian/Ubuntu: apt install mailutils"
        log_error "  RHEL/CentOS: yum install mailx"
        return 1
    fi
    return 0
}

################################################################################
# 3. EMAIL SENDING
################################################################################

# Send email notification
# Usage: send_email <subject> <message> [report_file]
send_email_notification() {
    local subject="$1"
    local message="$2"
    local report_file="${3:-}"
    
    # Get email configuration
    local email_to="${CONFIG[EMAIL_TO]}"
    local email_from="${CONFIG[EMAIL_FROM]:-multi-report-omv@$(hostname)}"
    local use_html="${CONFIG[EMAIL_USE_HTML]:-false}"
    
    # Validate recipient
    if [ -z "$email_to" ]; then
        log_error "EMAIL_TO not configured"
        return 1
    fi
    
    if ! validate_email "$email_to"; then
        log_error "Invalid email address: $email_to"
        return 1
    fi
    
    # Check mail command
    if ! check_mail_command; then
        return 1
    fi
    
    log_debug "Sending email to: $email_to"
    log_debug "  Subject: $subject"
    log_debug "  From: $email_from"
    log_debug "  HTML: $use_html"
    
    # Prepare email content
    local content_file=$(mktemp)
    
    if [ -n "$report_file" ] && [ -f "$report_file" ]; then
        # Use report file as content
        cat "$report_file" > "$content_file"
    else
        # Use message as content
        echo "$message" > "$content_file"
    fi
    
    # Send email
    local mail_result=0
    
    if [ "$use_html" = "true" ]; then
        # Send HTML email
        {
            echo "From: $email_from"
            echo "To: $email_to"
            echo "Subject: $subject"
            echo "Content-Type: text/html; charset=UTF-8"
            echo "MIME-Version: 1.0"
            echo ""
            cat "$content_file"
        } | sendmail -t 2>/dev/null
        mail_result=$?
        
        # Fallback to mail command if sendmail fails
        if [ $mail_result -ne 0 ]; then
            log_debug "sendmail failed, trying mail command"
            mail -s "$subject" -a "Content-Type: text/html" -r "$email_from" "$email_to" < "$content_file"
            mail_result=$?
        fi
    else
        # Send plain text email
        mail -s "$subject" -r "$email_from" "$email_to" < "$content_file"
        mail_result=$?
    fi
    
    # Cleanup
    rm -f "$content_file"
    
    if [ $mail_result -eq 0 ]; then
        log_info "Email sent successfully to $email_to"
        return 0
    else
        log_error "Failed to send email (exit code: $mail_result)"
        return 1
    fi
}

# Send test email
send_test_email() {
    local email_to="${CONFIG[EMAIL_TO]}"
    
    if [ -z "$email_to" ]; then
        echo "ERROR: EMAIL_TO not configured"
        return 1
    fi
    
    echo "Sending test email to: $email_to"
    
    local subject="[Multi-Report-OMV] Test Email"
    local message="This is a test email from Multi-Report-OMV.

Configuration:
  From: ${CONFIG[EMAIL_FROM]:-multi-report-omv@$(hostname)}
  To: $email_to
  HTML: ${CONFIG[EMAIL_USE_HTML]:-false}
  
System:
  Hostname: $(hostname)
  Date: $(date)
  
If you received this email, the email notification system is working correctly.
"
    
    if send_email_notification "$subject" "$message"; then
        echo "✓ Test email sent successfully"
        return 0
    else
        echo "✗ Failed to send test email"
        return 1
    fi
}

################################################################################
# 4. MODULE REGISTRATION
################################################################################

# Register email notification method with core notification system
if type register_notification_method &>/dev/null; then
    register_notification_method "email" "send_email_notification" "EMAIL_ENABLED"
    log_debug "Email notification method registered"
fi
