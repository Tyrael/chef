#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Steve Midgley (http://www.misuse.org/science)
# Copyright:: Copyright (c) 2009 Opscode, Inc.
# Copyright:: Copyright (c) 2008 Steve Midgley
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class Chef
  module Mixin
    # == Chef::Mixin::DeepMerge
    # Implements a deep merging algorithm for nested data structures.
    # ==== Notice:
    #   This code was originally imported from deep_merge by Steve Midgley.
    #   deep_merge is available under the MIT license from
    #   http://trac.misuse.org/science/wiki/DeepMerge
    module DeepMerge
      extend self

      def merge(first, second)
        first  = Mash.new(first)  unless first.kind_of?(Mash)
        second = Mash.new(second) unless second.kind_of?(Mash)

        DeepMerge.deep_merge(second, first, {:preserve_unmergeables => false})
      end

      def horizontal_merge(first, second)
        first  = Mash.new(first)  unless first.kind_of?(Mash)
        second = Mash.new(second) unless second.kind_of?(Mash)

        DeepMerge.deep_merge(second, first, {:preserve_unmergeables => false, :horizontal_precedence => true})
      end

      # Inherited roles use the knockout_prefix array subtraction functionality
      # This is likely to go away in Chef >= 0.11
      def role_merge(first, second)
        first  = Mash.new(first)  unless first.kind_of?(Mash)
        second = Mash.new(second) unless second.kind_of?(Mash)

        DeepMerge.deep_merge(second, first, {:preserve_unmergeables => false, :knockout_prefix => "!merge", :horizontal_precedence => true})
      end

      class InvalidParameter < StandardError; end

      # Deep Merge core documentation.
      # deep_merge! method permits merging of arbitrary child elements. The two top level
      # elements must be hashes. These hashes can contain unlimited (to stack limit) levels
      # of child elements. These child elements to not have to be of the same types.
      # Where child elements are of the same type, deep_merge will attempt to merge them together.
      # Where child elements are not of the same type, deep_merge will skip or optionally overwrite
      # the destination element with the contents of the source element at that level.
      # So if you have two hashes like this:
      #   source = {:x => [1,2,3], :y => 2}
      #   dest =   {:x => [4,5,'6'], :y => [7,8,9]}
      #   dest.deep_merge!(source)
      #   Results: {:x => [1,2,3,4,5,'6'], :y => 2}
      # By default, "deep_merge!" will overwrite any unmergeables and merge everything else.
      # To avoid this, use "deep_merge" (no bang/exclamation mark)
      #
      # Options:
      #   Options are specified in the last parameter passed, which should be in hash format:
      #   hash.deep_merge!({:x => [1,2]}, {:knockout_prefix => '!merge'})
      #   :preserve_unmergeables  DEFAULT: false
      #      Set to true to skip any unmergeable elements from source
      #   :knockout_prefix        DEFAULT: nil
      #      Set to string value to signify prefix which deletes elements from existing element
      #      A colon is appended when indicating a specific value, eg:
      #      :knockout_prefix => "dontmerge", is referenced as "dontmerge:foobar" in an array
      #   :sort_merged_arrays     DEFAULT: false
      #      Set to true to sort all arrays that are merged together
      #   :unpack_arrays          DEFAULT: nil
      #      Set to string value to run "Array::join" then "String::split" against all arrays
      #   :merge_debug            DEFAULT: false
      #      Set to true to get console output of merge process for debugging
      #
      # Selected Options Details:
      # :knockout_prefix => The purpose of this is to provide a way to remove elements
      #   from existing Hash by specifying them in a special way in incoming hash
      #    source = {:x => ['!merge:1', '2']}
      #    dest   = {:x => ['1', '3']}
      #    dest.ko_deep_merge!(source)
      #    Results: {:x => ['2','3']}
      #   Additionally, if the knockout_prefix is passed alone as a string, it will cause
      #   the entire element to be removed:
      #    source = {:x => '!merge'}
      #    dest   = {:x => [1,2,3]}
      #    dest.ko_deep_merge!(source)
      #    Results: {:x => ""}
      # :unpack_arrays => The purpose of this is to permit compound elements to be passed
      #   in as strings and to be converted into discrete array elements
      #   irsource = {:x => ['1,2,3', '4']}
      #   dest   = {:x => ['5','6','7,8']}
      #   dest.deep_merge!(source, {:unpack_arrays => ','})
      #   Results: {:x => ['1','2','3','4','5','6','7','8'}
      #   Why: If receiving data from an HTML form, this makes it easy for a checkbox
      #    to pass multiple values from within a single HTML element
      #
      # There are many tests for this library - and you can learn more about the features
      # and usages of deep_merge! by just browsing the test examples
      def deep_merge!(source, dest, options = {})
        # turn on this line for stdout debugging text
        merge_debug = options[:merge_debug] || false
        overwrite_unmergeable = !options[:preserve_unmergeables]
        knockout_prefix = options[:knockout_prefix] || nil
        raise InvalidParameter, "knockout_prefix cannot be an empty string in deep_merge!" if knockout_prefix == ""
        raise InvalidParameter, "overwrite_unmergeable must be true if knockout_prefix is specified in deep_merge!" if knockout_prefix && !overwrite_unmergeable
        # if present: we will split and join arrays on this char before merging
        array_split_char = options[:unpack_arrays] || false
        # request that we sort together any arrays when they are merged
        sort_merged_arrays = options[:sort_merged_arrays] || false
        di = options[:debug_indent] || ''
        # do nothing if source is nil
        return dest if source.nil?
        # if dest doesn't exist, then simply copy source to it
        if dest.nil? && overwrite_unmergeable
          dest = source; return dest
        end

        puts "#{di}Source class: #{source.class.inspect} :: Dest class: #{dest.class.inspect}" if merge_debug
        if source.kind_of?(Hash)
          puts "#{di}Hashes: #{source.inspect} :: #{dest.inspect}" if merge_debug
          source.each do |src_key, src_value|
            if dest.kind_of?(Hash)
              puts "#{di} looping: #{src_key.inspect} => #{src_value.inspect} :: #{dest.inspect}" if merge_debug
              if dest[src_key]
                puts "#{di} ==>merging: #{src_key.inspect} => #{src_value.inspect} :: #{dest[src_key].inspect}" if merge_debug
                dest[src_key] = deep_merge!(src_value, dest[src_key], options.merge(:debug_indent => di + '  '))
              else # dest[src_key] doesn't exist so we want to create and overwrite it (but we do this via deep_merge!)
                puts "#{di} ==>merging over: #{src_key.inspect} => #{src_value.inspect}" if merge_debug
                # NOTE: We are doing this via deep_merge! because the
                # src_value can still contain merge directives such as
                # knockout_prefix.
                # Historically we have been dup'ing the src_value here
                # and merging src_value with src_value.dup. This logic
                # is not applicable anymore because it results in
                # duplicates when merging two array values with
                # :horizontal_precedence = true.
                if src_value.nil?
                  # Nothing to compute with an extra deep_merge!
                  dest[src_key] = src_value
                else
                  dest[src_key] = deep_merge!(src_value, { }, options.merge(:debug_indent => di + '  '))
                end
              end
            else # dest isn't a hash, so we overwrite it completely (if permitted)
              if overwrite_unmergeable
                puts "#{di}  overwriting dest: #{src_key.inspect} => #{src_value.inspect} -over->  #{dest.inspect}" if merge_debug
                dest = overwrite_unmergeables(source, dest, options)
              end
            end
          end
        elsif source.kind_of?(Array)
          puts "#{di}Arrays: #{source.inspect} :: #{dest.inspect}" if merge_debug
          # if we are instructed, join/split any source arrays before processing
          if array_split_char
            puts "#{di} split/join on source: #{source.inspect}" if merge_debug
            source = source.join(array_split_char).split(array_split_char)
            if dest.kind_of?(Array)
              dest = dest.join(array_split_char).split(array_split_char)
            end
          end
          # if there's a naked knockout_prefix in source, that means we are to truncate dest
          ko_variants = [ knockout_prefix, "#{knockout_prefix}:" ]
          ko_variants.each do |ko|
            if source.index(ko)
              dest = clear_or_nil(dest); source.delete(ko)
            end
          end
          if dest.kind_of?(Array)
            if knockout_prefix
              print "#{di} knocking out: " if merge_debug
              # remove knockout prefix items from both source and dest
              source.delete_if do |ko_item|
                retval = false
                item = ko_item.respond_to?(:gsub) ? ko_item.gsub(%r{^#{knockout_prefix}:}, "") : ko_item
                if item != ko_item
                  print "#{ko_item} - " if merge_debug
                  dest.delete(item)
                  dest.delete(ko_item)
                  retval = true
                end
                retval
              end
              puts if merge_debug
            end
            puts "#{di} merging arrays: #{source.inspect} :: #{dest.inspect}" if merge_debug
            # Behavior of merging arrays has changed with CHEF-4631.
            # Old behavior was to deduplicate and merge the
            # arrays. New behavior is to concatanate the arrays if the
            # merge is happening on the same attribute precedence
            # level and pick the value from the higher precedence
            # level if merge is being done across the precedence
            # levels.
            # Old behavior can still be used by setting
            # :deep_merge_array_concat to false in config.
            if Chef::Config[:deep_merge_array_concat]
              # If :horizontal_precedence is set, this means we are
              # merging two arrays at the same precendence level so
              # concatanate them. Otherwise this is a merge across
              # precedence levels which means we will pick the one
              # from higher precedence level.
              if options[:horizontal_precedence]
                dest += source
              else
                dest = source
              end
            else
              # Pre CHEF-4631 behavior for array merging
              dest = dest | source
            end
            dest.sort! if sort_merged_arrays
          elsif overwrite_unmergeable
            puts "#{di} overwriting dest: #{source.inspect} -over-> #{dest.inspect}" if merge_debug
            dest = overwrite_unmergeables(source, dest, options)
          end
        else # src_hash is not an array or hash, so we'll have to overwrite dest
          puts "#{di}Others: #{source.inspect} :: #{dest.inspect}" if merge_debug
          dest = overwrite_unmergeables(source, dest, options)
        end
        puts "#{di}Returning #{dest.inspect}" if merge_debug
        dest
      end # deep_merge!

      # allows deep_merge! to uniformly handle overwriting of unmergeable entities
      def overwrite_unmergeables(source, dest, options)
        merge_debug = options[:merge_debug] || false
        overwrite_unmergeable = !options[:preserve_unmergeables]
        knockout_prefix = options[:knockout_prefix] || false
        di = options[:debug_indent] || ''
        if knockout_prefix && overwrite_unmergeable
          if source.kind_of?(String) # remove knockout string from source before overwriting dest
            if source == knockout_prefix
              src_tmp = ""
            else
              src_tmp = source.gsub(%r{^#{knockout_prefix}:},"")
            end
          elsif source.kind_of?(Array) # remove all knockout elements before overwriting dest
            src_tmp = source.delete_if {|ko_item| ko_item.kind_of?(String) && ko_item.match(%r{^#{knockout_prefix}:}) }
          else
            src_tmp = source
          end
          if src_tmp == source # if we didn't find a knockout_prefix then we just overwrite dest
            puts "#{di}#{src_tmp.inspect} -over-> #{dest.inspect}" if merge_debug
            dest = src_tmp
          else # if we do find a knockout_prefix, then we just delete dest
            puts "#{di}\"\" -over-> #{dest.inspect}" if merge_debug
            dest = ""
          end
        elsif overwrite_unmergeable
          dest = source
        end
        dest
      end

      def deep_merge(source, dest, options = {})
        deep_merge!(source.dup, dest.dup, options)
      end

      def clear_or_nil(obj)
        if obj.respond_to?(:clear)
          obj.clear
        else
          obj = nil
        end
        obj
      end

    end

  end
end

