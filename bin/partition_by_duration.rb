#!/usr/bin/env ruby

=begin
Script to take a list of mp4 files + duration, use ffmpeg2 to partition them
based on duration:

A: 0 to 130 seconds
B 131 to 200 seconds
C 201 to 280 seconds
D 281 to 370 seconds
E 371 to 454 seconds
F 454 to 560 seconds
G 561 to 630 seconds
H 631 to 940 seconds
I 941 to 1260 seconds
J 1261 to 1650 seconds
K 1651 to 1800 seconds

Clips over 1800 seconds will be partitioned into x number of 1800 second
segments, plus an additional modulus segment. 

General flow should be:

1. Iterate over file, reading filename and total duration in seconds.
2. If duration is under 1800 seconds, use case statement to determine dir.
3. If over 1800 seconds, get quotient and modulus and loop 1..quotient to partition file
	 into 1800 second segments, and an extra modulus segment.
4. Move segment should be separate routine that accepts filename and duration!

=end

durfile = ARGV[0]
clips = Array.new

def partition_clips(datadir,clip,duration)

	subdir = case duration
		when 0..130				then "A"
		when 131..200			then "B"
		when 201..280			then "C"
		when 281..370			then "D"
		when 371..454			then "E"
		when 455..560			then "F"
		when 561..630			then "G"
		when 631..940			then "H"
		when 941..1260		then "I"
		when 1261..1650		then "J"
		when 1651..1800		then "K"
	end

	newdir = datadir + "/#{subdir}"
	#make directory if it doesn't exist
	Dir.mkdir("#{datadir}/#{subdir}") unless File.exists?("#{datadir}/#{subdir}")
	puts "Clip #{clip} will be moved into subdir #{newdir}"
	`cp #{datadir}/#{clip} #{newdir}`
	#puts "mv #{datadir}/#{clip} #{newdir}" 

end

File.open(durfile) do |f|
	f.each_line do |mp4|
		datadir,clip,duration = mp4.match(/(^.+)\/(.+\.mp4)\s+(\d+)$/).captures
		duration = duration.to_i
		if duration <= 1800
			clips << "#{datadir}\t#{clip}\t#{duration}"
			#add to clip array
		else
			#get quotient and modulus for clip to determine for looping
			quot,modulus = duration.divmod(1800)
			for i in 1..quot
				segstart = (i-1)*1800
				segstart +=1 if segstart != 0
				dur = 1800
				newclip = clip.sub(/.mp4/,"_#{i}.mp4")
				ofil = "#{datadir}/" + newclip
				`ffmpeg2 -i #{datadir}/#{clip} -acodec copy -vcodec copy -ss #{segstart} -t #{dur} #{ofil}`
				clips << "#{datadir}\t#{newclip}\t#{dur}"

				if i == quot && modulus > 0#handle the modulus
					segstart = quot*1800+1
					newclip = clip.sub(/.mp4/,"_#{i+1}.mp4")
					ofil = "#{datadir}/" + newclip
					`ffmpeg2 -i #{datadir}/#{clip} -acodec copy -vcodec copy -ss #{segstart} -t #{modulus} #{ofil}`
					clips << "#{datadir}\t#{newclip}\t#{modulus}"
				end
			end
		end
	end
end

clips.each do |c|
	datadir,clip,duration = c.split("\t")
	duration = duration.to_i
	partition_clips(datadir,clip,duration)
end
