# ```
# class Model
#   include Clear::Model
#
#   has_many posts : Post, [ foreign_key: Model.underscore_name + "_id", no_cache : false]
#
#   has_one passport : Passport
#   has_many posts
# ```
module Clear::Model::HasRelations
  # The method `has_one` declare a relation
  # 1, 1 where the current model primary key is stored in the foreign table.
  # `primary_key` method (default: `self#pkey`) and `foreign_key` method
  # (default: table_name in singular, plus "_id" appended)
  # can be redefined
  #
  # Examples:
  # ```
  # model Passport
  #   column id : Int32, primary : true
  #   has_one user : User It assumes the table `users` have a field `passport_id`
  # end
  #
  # model Passport
  #   column id : Int32, primary : true
  #   has_one owner : User, foreign_key: "" # It assumes the table `users` have a field `passport_id`
  # end
  # ```
  macro has_one(name, foreign_key = nil, primary_key = nil)
    {% relation_type = name.type %}
    {% method_name = name.var.id %}

    # The method {{method_name}} is a `has_one` relation
    #   to {{relation_type}}
    def {{method_name}} : {{relation_type}}?
      %primary_key = {{(primary_key || "pkey").id}}
      %foreign_key =  {{foreign_key}} || ( self.class.table.to_s.singularize + "_id" )

      Clear::Model::Cache.instance.hit( "{{@type}}.{{method_name}}",
        %primary_key, {{relation_type}}
      ) do
        [ {{relation_type}}.query.where{ raw(%foreign_key) == %primary_key }.first ].compact
      end.first?
    end

    def {{method_name}}! : {{relation_type}}
      {{method_name}}.not_nil!
    end

    # Addition of the method for eager loading and N+1 avoidance.
    class Collection
      # Eager load the relation {{method_name}}.
      # Use it to avoid N+1 queries.
      def with_{{method_name}}(fetch_columns = false) : self
        before_query do
          %primary_key = {{(primary_key || "#{relation_type}.pkey").id}}
          %foreign_key =  {{foreign_key}} || ( {{@type}}.table.to_s.singularize + "_id" )

          #SELECT * FROM foreign WHERE foreign_key IN ( SELECT primary_key FROM users )
          sub_query = self.dup.clear_select.select("#{%primary_key}")

          {{relation_type}}.query.where{ raw(%foreign_key).in?(sub_query) }.each(fetch_columns: true) do |mdl|
            puts "Set {{@type}}.{{method_name}}.#{mdl.pkey}"

            Clear::Model::Cache.instance.set(
              "{{@type}}.{{method_name}}", mdl.attributes[%foreign_key], [mdl]
            )
          end
        end

        self
      end
    end
  end

  macro has_many(name, foreign_key = nil, primary_key = nil)
    {% relation_type = name.type %}
    {% method_name = name.var.id %}

    # The method {{method_name}} is a `has_one` relation
    #   to {{relation_type}}
    def {{method_name}} : {{relation_type}}::Collection
      %primary_key = {{(primary_key || "pkey").id}}
      %foreign_key =  {{foreign_key}} || ( self.class.table.to_s.singularize + "_id" )

      #Clear::Model::Cache.instance.hit( "{{relation_type}}.{{method_name}}",
      #  %primary_key, {{relation_type}}
      #) do
      {{relation_type}}.query \
        .tags({ "#{%foreign_key}" => "#{%primary_key}" }) \
        .where{ raw(%foreign_key) == %primary_key }
      #end
    end

    # Addition of the method for eager loading and N+1 avoidance.
    class Collection
      # Eager load the relation {{method_name}}.
      # Use it to avoid N+1 queries.
      def with_{{method_name}}(fetch_columns = false, &block : {{relation_type}}::Collection -> ) : self
        before_query do
          %primary_key = {{(primary_key || "#{relation_type}.pkey").id}}
          %foreign_key =  {{foreign_key}} || ( {{@type}}.table.to_s.singularize + "_id" )

          #SELECT * FROM foreign WHERE foreign_key IN ( SELECT primary_key FROM users )
          sub_query = self.dup.clear_select.select("#{%primary_key}")

          qry = {{relation_type}}.query.where{ raw(%foreign_key).in?(sub_query) }
          yield(qry)

          qry.each(fetch_columns: fetch_columns) do |mdl|
            Clear::Model::Cache.instance.set(
              "{{relation_type}}.{{method_name}}", mdl.pkey, [mdl]
            )
          end
        end

        self
      end

      def with_{{method_name}}(fetch_columns = false)
        with_{{method_name}}(fetch_columns){|q|} #empty block
      end
    end
  end

  # ```
  # class Model
  #   include Clear::Model
  #   belongs_to user : User, foreign_key: "the_user_id"
  #
  # ```
  macro belongs_to(name, foreign_key = nil, no_cache = false, key_type = Int32?)
    {% relation_type = name.type %}
    {% method_name = name.var.id %}
    {% foreign_key = foreign_key || relation_type.stringify.underscore + "_id" %}

    column {{foreign_key.id}} : {{key_type}}

    # The method {{method_name}} is a `belongs_to` relation
    #   to {{relation_type}}
    def {{method_name}} : {{relation_type}}?
      x = Clear::Model::Cache.instance.hit( "{{relation_type}}.{{method_name}}",
        self.{{foreign_key.id}}, {{relation_type}}
      ) do
        [ {{relation_type}}.query.where{ raw({{relation_type}}.pkey) == self.{{foreign_key.id}} }.first ].compact
      end
      x.first?
    end

    def {{method_name}}! : {{relation_type}}
      {{method_name}}.not_nil!
    end

    def {{method_name}}=(x : {{relation_type}}?)
      @{{foreign_key.id}}_field.value = x.pkey
    end

    # Adding the eager loading
    class Collection
      def with_{{method_name}}(fetch_columns = false) : self
        before_query do
          sub_query = self.dup.clear_select.select({{foreign_key.stringify}})
          #{{relation_type}}.query.where{ raw({{relation_type}}.pkey) == self.{{foreign_key.id}} }.first ]
          #SELECT * FROM users WHERE id IN ( SELECT user_id FROM posts )
          {{relation_type}}.query.where{ raw({{relation_type}}.pkey).in?(sub_query) } \
            .each(fetch_columns: fetch_columns) do |mdl|
            puts "Set {{relation_type}}.{{method_name}}.#{mdl.pkey}"
            Clear::Model::Cache.instance.set(
              "{{relation_type}}.{{method_name}}", mdl.pkey, [mdl]
            )
          end
        end

        self
      end
    end

  end
end
