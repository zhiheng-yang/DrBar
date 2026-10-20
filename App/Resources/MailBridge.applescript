-- DrBar's bridge to Mail.
--
-- The app calls these handlers with parameters, so text the user typed is never pasted into
-- script source. Nothing is sent unless the user pressed Send in DrBar:
-- composing and sending are separate calls, and the app only calls sendMessage right after
-- the user's click. Each handler gives up on Mail after 30 seconds, so a busy Mail cannot hold
-- DrBar for long.

-- Creates a message to the recipients without sending it, and returns its id. With a sender
-- address, Mail sends from that account; without one, from its default account.
on composeNewMessage(senderAddress, recipientNames, recipientAddresses, theSubject, theBody, attachmentPath)
	set attachmentFile to my fileFromPath(attachmentPath)
	with timeout of 30 seconds
		tell application "Mail"
			set newMessage to make new outgoing message with properties {subject:theSubject, content:theBody & linefeed & linefeed, visible:false}
			tell newMessage
				if senderAddress is not "" then set sender to my senderFor(senderAddress)
				repeat with i from 1 to count of recipientAddresses
					make new to recipient at end of to recipients with properties {name:item i of recipientNames, address:item i of recipientAddresses}
				end repeat
				if attachmentFile is not missing value then
					make new attachment with properties {file name:attachmentFile} at after the last paragraph
				end if
			end tell
			return id of newMessage
		end tell
	end timeout
end composeNewMessage

-- Creates a reply to the first message of the thread, so Mail fills in In-Reply-To and
-- References. The subject carries the time left, so it is set each time. The recipients are always
-- set again, because a reply to a message you sent yourself may be addressed to you, and the
-- group may have changed since. Returns -1 when the first message is gone.
on composeReply(firstMessageID, senderAddress, recipientNames, recipientAddresses, theSubject, theBody, attachmentPath)
	set attachmentFile to my fileFromPath(attachmentPath)
	with timeout of 30 seconds
		tell application "Mail"
			set originals to (messages of sent mailbox whose message id is firstMessageID)
			if (count of originals) is 0 then return -1
			set replyMessage to reply (item 1 of originals) without opening window
			tell replyMessage
				if senderAddress is not "" then set sender to my senderFor(senderAddress)
				set subject to theSubject
				set content to theBody & linefeed & linefeed
				delete every to recipient
				delete every cc recipient
				delete every bcc recipient
				repeat with i from 1 to count of recipientAddresses
					make new to recipient at end of to recipients with properties {name:item i of recipientNames, address:item i of recipientAddresses}
				end repeat
				if attachmentFile is not missing value then
					make new attachment with properties {file name:attachmentFile} at after the last paragraph
				end if
			end tell
			return id of replyMessage
		end tell
	end timeout
end composeReply

-- Sends a message created by one of the handlers above. Returns true on success.
on sendMessage(outgoingID)
	with timeout of 30 seconds
		tell application "Mail"
			set theMessage to first outgoing message whose id is outgoingID
			return send theMessage
		end tell
	end timeout
end sendMessage

-- Returns the Message-ID of a message sent to this recipient with this subject after the
-- given date, or "" when Mail has not filed it yet.
on findSentMessageID(theSubject, recipientAddress, sentAfter)
	with timeout of 30 seconds
		tell application "Mail"
			set candidates to (messages of sent mailbox whose subject is theSubject and date sent is greater than or equal to sentAfter)
			repeat with candidate in candidates
				repeat with theRecipient in (to recipients of candidate)
					if (address of theRecipient) is recipientAddress then return message id of candidate
				end repeat
			end repeat
		end tell
	end timeout
	return ""
end findSentMessageID

-- "Full Name <address>" with the name of the account in Mail that has this address, so the
-- email shows the user's name as Mail would.
on senderFor(senderAddress)
	with timeout of 30 seconds
		tell application "Mail"
			repeat with anAccount in accounts
				if (email addresses of anAccount) contains senderAddress then
					return (full name of anAccount) & " <" & senderAddress & ">"
				end if
			end repeat
		end tell
	end timeout
	return senderAddress
end senderFor

on fileFromPath(thePath)
	if thePath is "" then return missing value
	return POSIX file thePath
end fileFromPath
