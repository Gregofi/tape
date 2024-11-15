#!/bin/sh -ev

REPORT_FILE="/tmp/backup-report-file.txt"

address="<email-address>"
subject="Backup Report"
email_content=""

/usr/sbin/tape backup > /tmp/tape-stdout.txt 2> /tmp/tape-stderr.txt

if [ $? -ne 0 ]; then
	subject="[Attention Required!] ${subject}"
fi

email_content="
<h1>Backup completed</h1>:
<p>Stdout:</p>
<pre><code>
$(cat /tmp/tape-stdout.txt)
</pre></code>

<p>Stderr:</p>
<pre><code>
$(cat /tmp/tape-stderr.txt)
</pre></code>
"

rm /tmp/tape-stdout.txt /tmp/tape-stderr.txt

touch "${REPORT_FILE}"
printf "To: ${address}\n" >> "${REPORT_FILE}"
printf "Subject: ${subject}\n" >> "${REPORT_FILE}"
printf "MIME-Version: 1.0\n" >> "${REPORT_FILE}"
printf "Content-Type: text/html" >> "${REPORT_FILE}"
printf "\n" >> "${REPORT_FILE}"
printf "%s\n" "${email_content}" >> "${REPORT_FILE}"
cat "${REPORT_FILE}" | msmtp --read-recipients
rm "${REPORT_FILE}"
