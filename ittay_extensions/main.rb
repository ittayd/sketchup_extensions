# Copyright 2016 Trimble Navigation Limited
# Licensed under the MIT license

require 'sketchup.rb'
require 'set'

module Ittay
  module Extensions
	def self.scatter(entities, compdef, count, &randomizer)
		model = Sketchup.active_model
		model.start_operation "Scatter", true; 
		count.times do 
			# point = randomizers.inject(Struct.new(:point, :payload).new(Geom::Point3d.new, nil)) do |data, randomizer|
			#	randomizer.(data)
			#	data
			# end.point
			point = randomizer.call()
			puts "Inserting at #{point}" if @debug
			entities.add_instance(compdef, Geom::Transformation.new(point))
		end
		model.commit_operation
	end
	
	def self.lecture_scatter(entities, compdef, count, centers, lengths)
		scatter(entities, compdef, count) do 
			i = rand(centers.length)
			[:x, :y, :z].map do |prop| 
				centers[i].send(prop) + 
				#+ (Math.sin(rand(-90..0).degrees) + 1) 
				(1- Math.sqrt(rand(0..1000)/1000.0)) * 
					lengths[i].send(prop).sample
			end
		end
	end
	
    def self.rotate(right_projection_degree, left_projection_degree, back = false, reverse = false)
      # We need a reference to the currently active model. The SketchUp API
      # currently only let you work on the active model. Under Windows there
      # will be only one model open at a time, but under OS X there might be
      # multiple models open.
      # 
      # Beware that if there is no model open under OS X then `active_model`
      # will return nil. In this example we ignore that for simplicity.
      model = Sketchup.active_model

      # Whenever you make changes to the model you must take care to use
      # `model.start_operation` and `model.commit_operation` to wrap everything
      # into a single undo step. Otherwise the user risk not being able to undo
      # everything and loose work.
      # 
      # Making sure your model changes is undoable in a single undo step is a
      # requirement of the Extension Warehouse submission quality checks.
      # 
      # Note that the first argument name is a string that will be appended to
      # the Edit > Undo menu - so make sure you name your operations something
      # the users can understand.
      model.start_operation('Isometric Rotation', true)

	  top = Math::atan(Math::sqrt(Math::tan(right_projection_degree)/Math::tan(left_projection_degree))) # 45 degrees for 30/30 isometric
	  right = Math::asin(Math::tan(right_projection_degree) * Math::cos(top) / Math::sin(top)) # # (~35.264389) for 30/30 isometric
	  
	  if back
		top += Math::PI
		right = -right
	  end
	  
	  model.selection.each do |entity|
	    corner = entity.bounds.corner(0)
		t1 = Geom::Transformation.rotation(corner, [0,0,1], top)
		t2	 = Geom::Transformation.rotation(corner, [1,0,0], right) 
		
		t = t2 * t1
		if reverse
			t.invert!
		end
		entity.transform!(t)
	  end
      # Finally we are done and we close the operation. In production you will
      # want to catch errors and abort to clean up if your function failed.
      # But for simplicity we won't do this here.
      model.commit_operation
	
	end


    # This method rotates the selection
    def self.rotate_isometric
		rotate(30.degrees, 30.degrees)
	end
	
	def self.rotate_back_isometric
		rotate(30.degrees, 30.degrees, true)
    end

	def self.make_group
      # We need a reference to the currently active model. The SketchUp API
      # currently only let you work on the active model. Under Windows there
      # will be only one model open at a time, but under OS X there might be
      # multiple models open.
      # 
      # Beware that if there is no model open under OS X then `active_model`
      # will return nil. In this example we ignore that for simplicity.
      model = Sketchup.active_model

      # Whenever you make changes to the model you must take care to use
      # `model.start_operation` and `model.commit_operation` to wrap everything
      # into a single undo step. Otherwise the user risk not being able to undo
      # everything and loose work.
      # 
      # Making sure your model changes is undoable in a single undo step is a
      # requirement of the Extension Warehouse submission quality checks.
      # 
      # Note that the first argument name is a string that will be appended to
      # the Edit > Undo menu - so make sure you name your operations something
      # the users can understand.
      model.start_operation('Make Group', true)

	  group = model.entities.add_group(model.selection)

      # Finally we are done and we close the operation. In production you will
      # want to catch errors and abort to clean up if your function failed.
      # But for simplicity we won't do this here.
      model.commit_operation
    end

    def self.scale_dialog()
		input = UI.inputbox(["Scale?"], [""], "Enter scale")
		return nil unless input
		return input[0].to_f
	end 
	
	def self.valid(point) 
		point[0].nil? ? point[1] : point
	end
	  
	def self.scale_dimensions

      # We need a reference to the currently active model. The SketchUp API
      # currently only let you work on the active model. Under Windows there
      # will be only one model open at a time, but under OS X there might be
      # multiple models open.
      # 
      # Beware that if there is no model open under OS X then `active_model`
      # will return nil. In this example we ignore that for simplicity.
      model = Sketchup.active_model

      # Whenever you make changes to the model you must take care to use
      # `model.start_operation` and `model.commit_operation` to wrap everything
      # into a single undo step. Otherwise the user risk not being able to undo
      # everything and loose work.
      # 
      # Making sure your model changes is undoable in a single undo step is a
      # requirement of the Extension Warehouse submission quality checks.
      # 
      # Note that the first argument name is a string that will be appended to
      # the Edit > Undo menu - so make sure you name your operations something
      # the users can understand.
  	 
      model.start_operation('Create Scaled Dim', true)

	  scale = scale_dialog()
	  
	  model.selection.grep(Sketchup::DimensionLinear).each do |dim|
		puts "Scaling #{dim}" if @debug
	    dim.set_attribute('scaling', 'scale', scale)
		dim.set_attribute('scaling', 'parent_scale', dim.parent.bounds.diagonal)
		
		start_updating(dim)
	  end
	  
	  self.init_timer
	  
      # Finally we are done and we close the operation. In production you will
      # want to catch errors and abort to clean up if your function failed.
      # But for simplicity we won't do this here.
      model.commit_operation
    end
	
	def self.start_updating(dim) 
		@scaled_dims.add(dim)
	end 
	
	def self.debug=(enable)
		@debug = enable
	end
	
	def self.update_scaled_dims 
		model = Sketchup.active_model
		@scaled_dims.delete_if do |dim|
			dim.deleted? || dim.get_attribute('scaling', 'scale').nil?
		end

		scaled = @scaled_dims.map do |dim| 
			# Sketchup has a bug in which dimensions for scaled groups return text that is different than what actually is displayed. So can't rely on dim.text
			# current = dim.text
			current = dim.get_attribute('scaling', 'text')
			scale = dim.get_attribute('scaling', 'scale').to_f
			parent_scale = dim.get_attribute('scaling', 'parent_scale').to_f / dim.parent.bounds.diagonal
			#dim.text = ''
			distance = dim.end[1].distance_to_line([dim.start[1], dim.offset_vector])
			scaled = (distance * parent_scale * scale).to_l.to_s.sub('~ ', '') # (dim.start[1].distance(dim.end[1]).to_f * scale).to_l.to_s
			puts "#{distance.to_s.to_l.to_s} * #{parent_scale} * #{scale} = #{scaled}. Current=#{current}"  if @debug
			#puts "(#{dim.parent.instances[0]}, #{dim.parent.instances[0].scaled_size}, #{dim.parent.instances[0].unscaled_size})"
			#puts "(#{dim.parent.instances[0].parent}, #{dim.parent.instances[0].scaled_size}, #{dim.parent.instances[0].unscaled_size})"
			[dim, scaled] if scaled != current
		end.compact
		
		if scaled.any? 
			model.start_operation('Update Scaled Dim', true)
			scaled.each do |dim, scaled|
				# If the dimension is of a scaled group, say by 2, and the dimension says 10, then the dim.text method may return 5 (dimension before scale)
				# so if I scale the dimension, the scale is 5, but setting the text to 5 will make SU think nothing changed, so won't update the text property
				# and the dimension will still show 10.
				dim.text = 'bug' 
				dim.text = scaled
				dim.set_attribute('scaling', 'text', scaled)
			end
			model.commit_operation

		end
		model.selection.add()
	end
	
	def self.init_scaled_dims 
		
		@scaled_dims = Set.new
		
		model = Sketchup.active_model
	  
		model.entities.grep(Sketchup::DimensionLinear).each do |dim|
			if dim.get_attribute('scaling', 'scale')
				start_updating(dim)
			end
		end
	end
	
	def self.stop_timer
		UI.stop_timer(@timer)
		@timer = nil
	end
	
	def self.init_timer 
	  @timer ||= UI.start_timer(3, true) do 
		begin
			self.update_scaled_dims
		rescue 
			stop_timer
			raise 
		end
	  end
	end
	
	def self.offset_dim_by_edge
		ss = Sketchup.active_model.selection
		dim = ss.find{|e| e.class == Sketchup::DimensionLinear}
		edge = ss.find{|e| e.class == Sketchup::Edge}
		
		dim.offset_vector = edge.line[1]
	end
	
	def self.initialize_menu(menu) 
	  menu = menu.add_submenu("Ittay's")

      # We add the menu item directly to the root of the menu in this example.
      # But if you plan to add multiple items per extension we recommend you
      # group them into a sub-menu in order to keep things organized.
      menu.add_item('Rotate Isometric') {self.rotate_isometric}
	  
	  menu.add_item('Rotate Isometric^-1') {self.rotate_back_isometric}
	  
	  menu.add_item('Make Group') {self.make_group}
	  
	  menu.add_item('Scale Dimension') {self.scale_dimensions}
	  
 	  menu.add_item('Offset Dimension by Edge') {self.offset_dim_by_edge}

	end
	
	def self.init_context_menu(menu)
		sel = Sketchup.active_model.selection.first
		return if not sel
		menu.add_separator
		initialize_menu(menu)
	end
	
    # Here we add a menu item for the extension. Note that we again use a
    # load guard to prevent multiple menu items from accidentally being
    # created.
    unless file_loaded?(__FILE__)
	  
	  self.init_scaled_dims

	  
	  self.init_timer

	  
      # We fetch a reference to the top level menu we want to add to. Note that
      # we use "Plugins" here which was the old name of the "Extensions" menu.
      # By using "Plugins" you remain backwards compatible.
      menu = UI.menu('Plugins')
	  
	  initialize_menu(menu)	  
	  UI.add_context_menu_handler(&(method(:init_context_menu)))

      file_loaded(__FILE__)
    end

  end # module 
end # module 
